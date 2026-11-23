#!/usr/bin/env python3
# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

"""Capture isolated website examples with macOS window shadows. Requires Screen Recording permission."""
import argparse,json,os,shutil,subprocess,tempfile,time
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',required=True,type=Path)
parser.add_argument('--vector-inputs',type=Path)
args=parser.parse_args()
repo=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='moth-site-capture-',dir='/private/tmp') as directory:
    root=Path(directory);app=root/'Moth Site Examples.app';captures=root/'captures';captures.mkdir()
    subprocess.run(['ditto',str(repo/'Build/Moth.app'),str(app)],check=True)
    subprocess.run(['/usr/libexec/PlistBuddy','-c',f'Set CFBundleIdentifier com.thom.moth.site-examples.{os.getpid()}',str(app/'Contents/Info.plist')],check=True)
    subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True,capture_output=True)
    # The fixture dispatcher can read only files under its temporary configuration directory.
    web=repo.parent/'moth-web';shutil.copyfile(web/'assets-source/aircraft.png',root/'aircraft.png')
    command=['/usr/bin/open','-n','-W',str(app),'--stdout',str(root/'stdout.log'),'--stderr',str(root/'stderr.log'),'--env',f'MOTH_CONFIG_PATH={root}/config.toml','--env',f'MOTH_SITE_SCREENSHOT_DIR={captures}']
    if args.vector_inputs:
        inputs=root/'Inputs';inputs.mkdir()
        for name in ['before.toml','appearance.toml','nerd-fonts.txt']:shutil.copyfile(args.vector_inputs/name,inputs/name)
        command+=['--env',f'MOTH_VECTOR_INPUT_DIR={inputs}']
    command+=['--args','--site-screenshots','--native-window-capture']
    if args.vector_inputs:command+=['--vector-reference']
    process=subprocess.Popen(command);seen=set();deadline=time.monotonic()+180
    try:
        while process.poll() is None:
            if time.monotonic()>deadline:raise TimeoutError('Website capture timed out')
            request=captures/'window-capture-request.json'
            if request.exists():
                data=json.loads(request.read_text());path=Path(data['path'])
                if path.parent!=captures:raise ValueError('Unexpected capture path')
                if path not in seen:
                    seen.add(path);time.sleep(.25)
                    # Omit -o: the system supplies its own transparent corners and window shadow.
                    subprocess.run(['/usr/sbin/screencapture','-x','-l',str(data['windowID']),str(path)],check=True)
                    print(f'Captured {path.name}',flush=True)
            time.sleep(.05)
        if process.returncode:raise RuntimeError((root/'stderr.log').read_text())
        if not (captures/'manifest.json').exists():raise RuntimeError((root/'stderr.log').read_text())
        args.output.mkdir(parents=True,exist_ok=True)
        for source in captures.iterdir():
            if source.name!='window-capture-request.json':shutil.copyfile(source,args.output/source.name)
    finally:
        if process.poll() is None:process.terminate()
