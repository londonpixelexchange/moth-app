#!/usr/bin/env python3
# Copyright (c) 2026 T E Vaughan.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

"""Exercise launch and Cmd+N input through real helpers, using private fixture data."""
import json,os,signal,socket,struct,subprocess,tempfile,time
from pathlib import Path
app=Path(os.environ.get('MOTH_TEST_APP',Path(__file__).resolve().parents[1]/'Build/Moth.app')).resolve()
with tempfile.TemporaryDirectory(prefix='moth-recovery-host-',dir='/private/tmp') as tmp:
 root=Path(tmp);fixture=root/'Moth Focus Test.app'
 subprocess.run(['ditto',str(app),str(fixture)],check=True)
 subprocess.run(['/usr/libexec/PlistBuddy','-c',f'Set CFBundleIdentifier dev.getmoth.focus-test.{os.getpid()}',str(fixture/'Contents/Info.plist')],check=True)
 subprocess.run(['codesign','--force','--deep','--sign','-','--preserve-metadata=flags',str(fixture)],check=True,stdout=subprocess.DEVNULL)
 (root/'config.toml').write_text("shell = '/bin/sh'\ncloseOnExit = false\nshowLayoutsOnLaunch = false\n[closeConfirmation]\nenabled = false\n[updates]\ncheckAtLaunch = false\n[advanced]\nloginShell = false\nsessionRecovery = true\n[advanced.environment]\nPS1 = 'focus-test$ '\nENV = ''\nBASH_ENV = ''\n")
 launch=subprocess.Popen(['/usr/bin/open','-n','-W',str(fixture),'--stdout',str(root/'stdout.log'),'--stderr',str(root/'stderr.log'),'--env',f'MOTH_RECOVERY_TEST_ROOT={root}','--env','MOTH_RECOVERY_TEST_FOCUS=1','--args','--recovery-test-host'])
 try:
  deadline=time.monotonic()+25
  while not (root/'focus-results.json').exists():
   if launch.poll() is not None:raise AssertionError('Focus test exited without results: '+(root/'stderr.log').read_text())
   if time.monotonic()>deadline:raise AssertionError('Focus test timed out')
   time.sleep(.05)
  result=json.loads((root/'focus-results.json').read_text());launch.wait(timeout=5)
  print(json.dumps(result,indent=2));assert len(result)==13 and all(result.values()),result
  print('13/13 real-helper window focus and first-keystroke checks passed')
 finally:
  for record in (root/'Sessions').glob('*.json'):
   try:
    item=json.loads(record.read_text())
    if 'socket' in item:
     with socket.socket(socket.AF_UNIX) as connection:
      connection.settimeout(1);connection.connect(item['socket']);connection.sendall(b'T'+struct.pack('!I',0))
   except (OSError,ValueError):pass
  if launch.poll() is None:
   expected=(fixture/'Contents/MacOS/Moth').resolve()
   for line in subprocess.check_output(['/bin/ps','-axo','pid=,comm='],text=True).splitlines():
    parts=line.strip().split(None,1)
    if len(parts)==2 and Path(parts[1]).resolve()==expected:
     try:os.kill(int(parts[0]),signal.SIGTERM)
     except ProcessLookupError:pass
   launch.terminate()
