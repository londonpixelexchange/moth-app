#!/usr/bin/env python3
# Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

"""Kill an isolated GUI app, relaunch it, and check the original PTYs and layout."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

APP = Path(os.environ.get('MOTH_TEST_APP', Path(__file__).resolve().parents[1] / 'Build/Moth.app')).resolve()

def wait(path, limit=20):
    deadline = time.monotonic()+limit
    while not path.exists():
        if time.monotonic() > deadline: raise AssertionError(f'Timed out waiting for {path.name}')
        time.sleep(.05)

with tempfile.TemporaryDirectory(prefix='moth-recovery-host-',dir='/private/tmp') as tmp:
    root = Path(tmp)
    fixture = root/'Moth Recovery Test.app'
    subprocess.run(['ditto',str(APP),str(fixture)],check=True)
    if os.environ.get('MOTH_PRESERVE_SIGNATURE') != '1':
        subprocess.run(['/usr/libexec/PlistBuddy','-c',f'Set CFBundleIdentifier dev.getmoth.recovery-test.{os.getpid()}',str(fixture/'Contents/Info.plist')],check=True)
        subprocess.run(['codesign','--force','--deep','--sign','-',str(fixture)],check=True,stdout=subprocess.DEVNULL)
    (root/'config.toml').write_text('''shell = '/bin/sh'
theme = 'moth-dark'
closeOnExit = false
showLayoutsOnLaunch = false
[closeConfirmation]
enabled = false
[advanced]
loginShell = false
[advanced.environment]
PS1 = 'moth-test$ '
''')
    # Use zsh with an isolated empty ZDOTDIR; shell history files are never touched.
    with (root/'config.toml').open('a') as f: f.write(f"ZDOTDIR = '{root}'\n")
    launches = []
    def launch():
        process = subprocess.Popen(['/usr/bin/open','-n','-W',str(fixture),'--stdout',str(root/'stdout.log'),'--stderr',str(root/'stderr.log'),'--env',f'MOTH_RECOVERY_TEST_ROOT={root}','--env',f'MOTH_RECOVERY_TEST_PANES={os.environ.get("MOTH_RECOVERY_TEST_PANES","3")}','--env',f'MOTH_RECOVERY_TEST_MAXIMIZED={os.environ.get("MOTH_RECOVERY_TEST_MAXIMIZED","0")}','--args','--recovery-test-host'])
        launches.append(process)
    expected = None
    try:
        launch(); wait(root/'expected.json'); expected=json.loads((root/'expected.json').read_text())
        os.kill(expected['app'],signal.SIGKILL)
        launches[0].wait(timeout=8)
        time.sleep(2.5)
        (root/'keep-request').touch()
        launch(); wait(root/'kept-results.json'); launches[-1].wait(timeout=8)
        kept=json.loads((root/'kept-results.json').read_text()); assert all(kept.values()), kept
        for pid in expected['shells']: os.kill(pid,0)
        assert (root/'Sessions/recovery.json').exists(), 'Quit and Keep Sessions lost recovery state'
        launch(); wait(root/'results.json')
        result=json.loads((root/'results.json').read_text())
        launches[-1].wait(timeout=8)
        print(json.dumps(result,indent=2))
        assert all(result.values()), 'Full app recovery failed'
        assert not (root/'Sessions/recovery.json').exists(), 'Normal quit retained a recovery manifest'
        deadline=time.monotonic()+3
        while time.monotonic()<deadline:
            alive=[]
            for pid in expected['shells']:
                try: os.kill(pid,0); alive.append(pid)
                except ProcessLookupError: pass
            if not alive: break
            time.sleep(.05)
        assert not alive, 'Normal quit left running shells behind' 
        print(f'{len(result)}/{len(result)} full app crash/relaunch checks passed; Quit and Keep Sessions retained processes; normal quit cleared recovery state')
    except Exception:
        for name in ['stdout.log','stderr.log','diagnostics.txt']:
            if (root/name).exists(): print((root/name).read_text())
        raise
    finally:
        for record in (root/'Sessions').glob('*.json'):
            try:
                value=json.loads(record.read_text())
                if 'socket' in value:
                    import socket,struct
                    sock=socket.socket(socket.AF_UNIX); sock.settimeout(1); sock.connect(value['socket']); sock.sendall(b'T'+struct.pack('!I',0)); sock.close()
            except (OSError,ValueError): pass
        for pid in (expected or {}).get('shells',[]):
            try: os.kill(pid,signal.SIGKILL)
            except ProcessLookupError: pass
        for process in launches:
            if process.poll() is None: process.terminate()
