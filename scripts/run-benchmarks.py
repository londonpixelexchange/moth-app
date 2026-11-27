#!/usr/bin/env python3
# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: GPL-3.0-or-later
# Licensed under GNU GPL version 3 or later. See LICENSE.

"""Repeatable, isolated Moth Release benchmark; only benchmark-owned processes are stopped."""
import argparse, csv, datetime, hashlib, json, math, os, pathlib, platform, plistlib, shutil, signal, subprocess, tempfile, time

def command(*args):
    return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL).strip()

def validate_trial(trial, mode, run, identity, info, quick, payload_sizes):
    if not trial.get('complete') or trial.get('phase') != 'complete' or trial.get('error'):
        raise ValueError('Cannot accept an incomplete or failed benchmark trial')
    if (trial.get('version'), str(trial.get('build')), trial.get('commit')) != (info['CFBundleShortVersionString'], str(info['CFBundleVersion']), identity['commit']):
        raise ValueError('Benchmark app identity does not match the selected release')
    if trial.get('mode') != mode or trial.get('run') != run or bool(trial.get('quickWorkloadValidation')) != quick:
        raise ValueError('Benchmark mode, run number or workload protocol does not match')
    stages = {stage['name']: stage for stage in trial['stages']}
    required = ['output_plain', 'output_ansi', 'render_visible_grid']
    if not quick:
        required += ['idle_visible', 'idle_minimized']
        if mode == 'default': required += ['idle_effects_disabled_after_use']
    if len(stages) != len(trial['stages']) or set(stages) != set(required):
        raise ValueError('Benchmark stages do not match the full protocol')
    if not quick:
        for name, seconds in [('idle_visible',15), ('idle_minimized',10)] + ([('idle_effects_disabled_after_use',10)] if mode == 'default' else []):
            stage = stages[name]
            if stage['durationSeconds'] < seconds-0.1 or not math.isfinite(stage['cpuPercentOneCore']) or stage['cpuPercentOneCore'] < 0:
                raise ValueError('Invalid idle sampling interval')
            if name != 'idle_minimized' and (stage['windowOccluded'] or not stage['windowVisible']):
                raise ValueError('Cannot accept a covered-window measurement')
    for name in ['plain','ansi']:
        stage = stages['output_'+name]
        if stage['verifiedCommandExitStatus'] != 0 or stage['receivedPTYBytes'] < stage['bytes'] or stage['bytes'] != payload_sizes[name+'.txt'] or stage['scrollbackPosition'] != 10000:
            raise ValueError('Cannot accept an incomplete PTY workload')
        if not math.isfinite(stage['mibPerSecond']) or stage['mibPerSecond'] <= 0:
            raise ValueError('Invalid PTY throughput measurement')
    if not math.isfinite(trial['processToReadySeconds']) or trial['processToReadySeconds'] <= 0:
        raise ValueError('Invalid shell-ready time')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--runs',type=int,default=3)
    parser.add_argument('--app',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[1]/'Build/ReleaseSigned/Moth.app')
    parser.add_argument('--resume',action='store_true',help='Reuse completed, validated trials from the same release')
    parser.add_argument('--visibility-retries',type=int,default=2,help='Extra attempts after a rejected visibility sample')
    parser.add_argument('--quick',action='store_true',help='Validate workload completion without idle sampling')
    parser.add_argument('--modes',nargs='+',choices=['default','minimal'],default=['default','minimal'])
    parser.add_argument('--output',type=pathlib.Path,default=pathlib.Path(__file__).resolve().parents[1]/'Build/Benchmarks/results')
    args=parser.parse_args(); args.output.mkdir(parents=True,exist_ok=True)
    if args.runs < 1: parser.error('--runs must be positive')
    if args.visibility_retries < 0: parser.error('--visibility-retries must not be negative')
    original=args.app.resolve()
    if not original.is_dir(): raise SystemExit('Supply the released app with --app')
    identity=json.loads((original/'Contents/Resources/BuildIdentity.json').read_text())
    if identity.get('dirty') is not False: raise SystemExit('Benchmark requires an app built from a clean commit')
    info=plistlib.loads((original/'Contents/Info.plist').read_bytes())
    subprocess.run(['codesign','--verify','--deep','--strict',str(original)],check=True)
    binary_hash=hashlib.sha256((original/'Contents/MacOS/Moth').read_bytes()).hexdigest()
    root=pathlib.Path(tempfile.mkdtemp(prefix='moth-performance-'))
    app=original
    # Prevent sleep during the visible-window samples without changing preferences.
    awake=subprocess.Popen(['/usr/bin/caffeinate','-di','-w',str(os.getpid())])
    payload=root/'payloads'; payload.mkdir()
    with (payload/'plain.txt').open('wb') as plain,(payload/'ansi.txt').open('wb') as ansi:
        for i in range(65536):
            text=(f'{i:06d} '+('moth terminal benchmark ' * 4)[:72]).encode()
            plain.write(text+b'\r\n')
            ansi.write(f'\x1b[38;2;{i%256};{(i*7)%256};{(i*13)%256}m'.encode()+text+b'\x1b[0m\r\n')
    hardware_info=json.loads(command('/usr/sbin/system_profiler','SPHardwareDataType','-json'))['SPHardwareDataType'][0]
    cpu_description=hardware_info['number_processors']
    logical_cpus=int(cpu_description.split(':')[0].removeprefix('proc '))
    memory=hardware_info['physical_memory'].split()
    memory_scale={'GB':1024**3,'TB':1024**4}[memory[1]]
    hardware={'macOS':command('sw_vers','-productVersion'),'build':command('sw_vers','-buildVersion'),'architecture':platform.machine(),
              'model':hardware_info['machine_model'],'cpu':hardware_info['chip_type'],
              'memoryBytes':int(float(memory[0])*memory_scale),'logicalCPUs':logical_cpus}
    package_files=[p for p in original.rglob('*') if p.is_file()]
    package={'logicalBytes':sum(p.stat().st_size for p in package_files),'allocatedBytes':sum(p.stat().st_blocks*512 for p in package_files)}
    payload_sizes={p.name:p.stat().st_size for p in payload.glob('*.txt')}
    manifest={'releaseIdentity':identity,'executableSHA256':binary_hash,'hardware':hardware,'payloads':payload_sizes,'quickWorkloadValidation':args.quick}
    manifest_path=args.output/'run-manifest.json'
    if manifest_path.exists() and json.loads(manifest_path.read_text()) != manifest:
        raise SystemExit('Output folder belongs to a different release, machine or workload protocol')
    manifest_path.write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    results=[]; owned_pid=None; launch=None
    def stop_owned(pid):
        if not pid:return
        try:
            path=command('/bin/ps','-p',str(pid),'-o','comm=')
            if pathlib.Path(path).resolve()==(app/'Contents/MacOS/Moth').resolve(): os.kill(pid,signal.SIGTERM)
        except (subprocess.CalledProcessError,ProcessLookupError):pass
    try:
        # Alternate order to reduce systematic effects from thermal/cache drift.
        trials=[(run,mode) for run in range(1,args.runs+1) for mode in (args.modes if run%2 else list(reversed(args.modes)))]
        for run,mode in trials:
            saved=args.output/f'{mode}-{run}.json'
            if saved.exists():
                if not args.resume: raise RuntimeError('Existing results found; use --resume or a new output folder')
                current=json.loads(saved.read_text())
                validate_trial(current,mode,run,identity,info,args.quick,payload_sizes)
                results.append(current)
                print(f'{mode} run {run}: reused completed trial',flush=True)
                continue
            for attempt in range(1,args.visibility_retries+2):
                directory=root/f'{mode}-{run}-attempt-{attempt}'; directory.mkdir(); report=directory/'result.json'
                params=['/usr/bin/open','-n','-W',str(app),'--stdout',str(directory/'stdout.log'),'--stderr',str(directory/'stderr.log')]
                for key,value in {'MOTH_CONFIG_PATH':str(directory/'config.toml'),'MOTH_BENCH_RESULT':str(report),'MOTH_BENCH_PAYLOADS':str(payload),'MOTH_BENCH_MODE':mode,'MOTH_BENCH_QUICK':'1' if args.quick else '0'}.items():params+=['--env',key+'='+value]
                params+=['--args','--benchmark']
                start=time.monotonic(); launch=subprocess.Popen(params); last_phase=None; first_ready=None; owned_pid=None; visibility_rejected=False
                while time.monotonic()-start<110:
                    if report.exists():
                        try: current=json.loads(report.read_text())
                        except (json.JSONDecodeError,FileNotFoundError):time.sleep(.05);continue
                        owned_pid=current.get('pid'); phase=current.get('phase')
                        if phase!=last_phase:
                            print(f'{mode} run {run}, attempt {attempt}: {phase}',flush=True);last_phase=phase
                        if first_ready is None and phase not in ['starting',None]:first_ready=time.monotonic()-start
                        if current.get('complete'):
                            current['run']=run;current['launchServicesToObservedReadySeconds']=first_ready
                            current['measuredAtUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat()
                            break
                        if current.get('error'):
                            stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
                            failure=f'failed-{mode}-{run}-{stamp}-attempt-{attempt}'
                            (args.output/(failure+'.json')).write_text(json.dumps(current,indent=2,sort_keys=True))
                            for name in ['stdout.log','stderr.log']:
                                if (directory/name).exists(): shutil.copy2(directory/name,args.output/(failure+'-'+name))
                            if str(current['error']).startswith('Visible-window sample rejected:'):
                                visibility_rejected=True
                                break
                            raise RuntimeError(current['error'])
                    if launch.poll() is not None:
                        error_log=directory/'stderr.log'
                        detail=error_log.read_text() if error_log.exists() else 'LaunchServices did not launch the app. Run this command from a normal macOS Terminal.'
                        raise RuntimeError('Benchmark exited early: '+detail)
                    time.sleep(.05)
                else:raise RuntimeError('Benchmark timeout')
                exit_status=launch.wait(timeout=5);owned_pid=None
                if visibility_rejected:
                    if attempt>args.visibility_retries:
                        raise RuntimeError('Visibility retries exhausted. Keep the desktop unlocked and benchmark window uncovered, then rerun with --resume.')
                    print('Rejected trial retained for diagnostics; retrying this trial in five seconds. Keep its window uncovered.',flush=True)
                    time.sleep(5)
                    continue
                if exit_status != 0: raise RuntimeError('Benchmark app exited unsuccessfully')
                validate_trial(current,mode,run,identity,info,args.quick,payload_sizes)
                results.append(current)
                saved.write_text(json.dumps(current,indent=2,sort_keys=True))
                for name in ['stdout.log','stderr.log']:
                    shutil.copy2(directory/name,args.output/f'{mode}-{run}-{name}')
                time.sleep(1)
                break
    finally:
        stop_owned(owned_pid)
        if launch and launch.poll() is None:launch.terminate()
        awake.terminate()
        awake.wait(timeout=5)
        shutil.rmtree(root,ignore_errors=True)
    assert hashlib.sha256((original/'Contents/MacOS/Moth').read_bytes()).hexdigest()==binary_hash, 'Released executable changed during measurement'
    all_results={'measuredAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'releaseIdentity':identity,'executableSHA256':binary_hash,'signaturePreserved':True,'hardware':hardware,'package':package,'trials':results,'method':{'quickWorkloadValidation':args.quick,'idleVisibleSeconds':0 if args.quick else 15,'idleMinimizedSeconds':0 if args.quick else 10,'warmupSeconds':0.3 if args.quick else 3,'launchType':'warm, clean zsh without user startup files','scope':'app process only; shell footprint separately sampled','payloads':payload_sizes}}
    (args.output/'results.json').write_text(json.dumps(all_results,indent=2,sort_keys=True))
    rows=[]
    for trial in results:
        for stage in trial['stages']:rows.append({'mode':trial['mode'],'run':trial['run'],**stage})
    keys=sorted(set().union(*(r.keys() for r in rows)))
    with (args.output/'measurements.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=keys);writer.writeheader();writer.writerows(rows)
    print('Results: '+str(args.output/'results.json'),flush=True)
if __name__=='__main__':main()
