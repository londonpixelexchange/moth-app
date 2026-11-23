#!/usr/bin/env python3
# Copyright (c) 2026 Thomas Edward Vaughan, trading as London Pixel Exchange.
# SPDX-License-Identifier: LicenseRef-Moth-SAL-1.0
# Source-available under the Moth Source-Available Licence 1.0. See LICENSE.

"""Exercise the actual bundled PTY helper, including loss of its launching client.

Uses an isolated temporary folder and /bin/sh; never touches Moth preferences.
"""
import json
import os
from pathlib import Path
import select
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

APP = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / 'Build/Moth.app/Contents/MacOS/Moth').resolve()

def send(sock, kind, body=b''):
    sock.sendall(kind.encode() + struct.pack('!I', len(body)) + body)

def exact(sock, n):
    result = b''
    while len(result) < n:
        more = sock.recv(n-len(result))
        if not more:
            raise EOFError('session disconnected')
        result += more
    return result

def receive(sock):
    header = exact(sock, 5)
    return chr(header[0]), exact(sock, struct.unpack('!I', header[1:])[0])

def connect(path):
    sock = socket.socket(socket.AF_UNIX)
    sock.settimeout(5)
    sock.connect(str(path)); send(sock,'B')
    kind, body = receive(sock)
    assert kind == 'H' and len(body) == 20
    return sock, struct.unpack('!IIIII', body)

def collect(sock, marker=None, replay=False):
    result = b''; kinds = []; deadline = time.monotonic()+8
    while time.monotonic() < deadline:
        kind, body = receive(sock); kinds.append(kind)
        if kind in ('O', 'P'):
            assert len(body) >= 8
            result += body[8:]
            if kind == 'O' and b'\x1b[6n' in body[8:]: send(sock,'I',b'\x1b[1;1R')
            if kind == 'O' and b'\x1b[c' in body[8:]: send(sock,'I',b'\x1b[?1;2c')
            send(sock, 'A', body[:8])
        if replay and kind == 'E':
            return result, kinds
        if marker and marker in result:
            return result, kinds
    raise AssertionError(f'timed out waiting for {marker!r}: {result[-500:]!r}')

def wait_path(path):
    deadline = time.monotonic()+15
    while not path.exists():
        if time.monotonic() > deadline: raise AssertionError('helper did not start')
        time.sleep(.01)

def driver(root):
    # This process represents the GUI: it starts its helper, then is killed by the test.
    helper = subprocess.Popen([str(APP), '--session-broker', str(root/'pty'), '24', '80', '/bin/sh'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env={**os.environ,'TERM':'xterm-256color','COLORTERM':'truecolor','PS1':'moth-test$ '})
    (root/'helper.json').write_text(json.dumps({'helper':helper.pid}))
    wait_path(root/'pty')
    print('Helper listening',flush=True)
    sock, info = connect(root/'pty'); initial, _ = collect(sock, replay=True)
    if b'moth-test$ ' not in initial: collect(sock,b'moth-test$ ')
    send(sock,'I',b'set +H; stty -echo\r')
    collect(sock,b'moth-test$ ')
    print('Connected',info,flush=True)
    send(sock,'I', b"stty -echo; printf 'SHELL=%s\\n' $$; (sleep 1; printf 'BACKGROUND_DONE\\n'; sleep 20) & printf 'JOB=%s\\n' $!; sleep 2; printf 'FOREGROUND_DONE\\n'\r")
    output, _ = collect(sock, b'JOB=')
    print('Output',repr(output),flush=True)
    # Finish any partial JOB line before publishing the IDs.
    while not any(line.startswith(b'JOB=') and line[4:].strip().isdigit() for line in output.splitlines()):
        more, _ = collect(sock, b'\n'); output += more
    job = int(next(line.split(b'=')[1] for line in output.splitlines() if line.startswith(b'JOB=') and line[4:].strip().isdigit()))
    (root/'ready.json').write_text(json.dumps({'helper': helper.pid, 'shell': info[0], 'job': job}))
    while True: time.sleep(1)

if len(sys.argv) > 2 and sys.argv[2] == '--driver':
    driver(Path(sys.argv[3])); sys.exit(0)

checks = {}
with tempfile.TemporaryDirectory(prefix='moth-recovery-', dir='/tmp') as directory:
    root = Path(directory)
    gui = subprocess.Popen([sys.executable, __file__, str(APP), '--driver', str(root)])
    info = None; sock = None
    try:
        wait_path(root/'ready.json'); info = json.loads((root/'ready.json').read_text())
        os.kill(gui.pid, signal.SIGKILL); gui.wait()
        time.sleep(2.3)
        for key in ('helper', 'shell', 'job'): os.kill(info[key], 0)
        checks['helperShellAndBackgroundJobSurviveClientSIGKILL'] = True
        sock, hello = connect(root/'pty')
        checks['reattachesToOriginalShellPID'] = hello[0] == info['shell']
        output, kinds = collect(sock, replay=True)
        checks['replaysAcknowledgedOutputWithoutRepeatingReplies'] = 'P' in kinds
        checks['retainsOutputProducedWhileDisconnected'] = b'BACKGROUND_DONE' in output and b'FOREGROUND_DONE' in output
        send(sock, 'R', struct.pack('!II', 33, 101))
        send(sock, 'I', b"printf 'REATTACHED=%s\\n' $$; stty size\r")
        output, _ = collect(sock, b'33 101')
        checks['inputAndResizeWorkAfterReattachment'] = f'REATTACHED={info["shell"]}'.encode() in output
        send(sock, 'I', b"printf '\\033[?1049h\\033[31mALT_RECOVERY\\033[0m'; printf '\\033[6n'\r")
        output, _ = collect(sock, b'ALT_RECOVERY')
        # ACKs must reach the helper before simulating another disconnect.
        time.sleep(.1); sock.close(); sock = None; time.sleep(.15)
        sock, hello = connect(root/'pty'); output, kinds = collect(sock, replay=True)
        checks['replaysAlternateScreenAndANSISequences'] = b'\x1b[?1049h' in output and b'\x1b[31mALT_RECOVERY' in output
        # An unrelated second GUI must not steal an already attached session.
        rejected = socket.socket(socket.AF_UNIX); rejected.settimeout(2); rejected.connect(str(root/'pty')); send(rejected,'B')
        checks['rejectsConcurrentSecondClient'] = rejected.recv(1) == b''; rejected.close()
        mode = (root/'pty').stat().st_mode & 0o777
        checks['sessionSocketIsPrivate'] = mode == 0o600
        send(sock, 'T'); sock.close(); sock = None
        deadline = time.monotonic()+4
        while (root/'pty').exists() and time.monotonic() < deadline: time.sleep(.02)
        checks['explicitCloseRemovesSocket'] = not (root/'pty').exists()
        # The socket is removed before the helper finishes waiting for the shell.
        # Give signal delivery and child reaping their own bounded deadline.
        for key, check in [('shell','explicitCloseEndsShell'),('job','explicitCloseEndsBackgroundJob')]:
            deadline = time.monotonic()+4
            while True:
                try: os.kill(info[key],0)
                except ProcessLookupError: checks[check] = True; break
                if time.monotonic() >= deadline:
                    checks[check] = False
                    subprocess.run(['ps','-o','pid,ppid,pgid,stat,comm','-p',str(info[key])])
                    break
                time.sleep(.02)
    finally:
        if sock: sock.close()
        if gui.poll() is None: gui.kill(); gui.wait()
        if info is None and (root/'helper.json').exists(): info = json.loads((root/'helper.json').read_text())
        if info:
            for key in ('job','shell','helper'):
                if key not in info: continue
                try: os.kill(info[key],signal.SIGKILL)
                except ProcessLookupError: pass
with tempfile.TemporaryDirectory(prefix='moth-recovery-exit-',dir='/tmp') as directory:
    path = Path(directory)/'pty'
    helper = subprocess.Popen([str(APP),'--session-broker',str(path),'24','80','/bin/sh','-c',"printf 'FINAL_OUTPUT\\n'; sleep 0.2; exit 7"],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        wait_path(path); time.sleep(.4); sock, hello = connect(path)
        output, _ = collect(sock,replay=True)
        kind, body = receive(sock)
        checks['recoversFinalOutputAndExitCodeWhileDisconnected'] = b'FINAL_OUTPUT' in output and kind == 'X' and struct.unpack('!I',body)[0] == 7
        sock.close(); helper.wait(timeout=3)
    finally:
        if helper.poll() is None: helper.kill(); helper.wait()
with tempfile.TemporaryDirectory(prefix='moth-recovery-bound-',dir='/tmp') as directory:
    path=Path(directory)/'pty'; done=Path(directory)/'ready'
    script=f"dd if=/dev/zero bs=65536 count=1100 2>/dev/null; touch '{done}'; sleep 30"
    helper=subprocess.Popen([str(APP),'--session-broker',str(path),'24','80','/bin/sh','-c',script],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    try:
        wait_path(done); sock,hello=connect(path); retained=0
        while True:
            kind,body=receive(sock)
            if kind in ('O','P'): retained+=len(body)-8
            if kind=='E': break
        checks['recoveryJournalIsBoundedAndReportsTruncation']=hello[4]==1 and 0<retained<=64*1024*1024
        send(sock,'T'); sock.close(); helper.wait(timeout=3)
    finally:
        if helper.poll() is None: helper.kill(); helper.wait()
print(json.dumps(checks,indent=2))
failed = [name for name, passed in checks.items() if not passed]
print(f'{len(checks)-len(failed)}/{len(checks)} process recovery checks passed')
if failed: sys.exit(1)
