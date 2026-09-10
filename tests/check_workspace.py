"""Opt-in live regression check; briefly switches workspaces, then restores them.

Run `python3 tests/check_workspace.py` from a running Omarchy session with the
drawer closed and another regular workspace on the current monitor.
"""

import json
import subprocess
import time


def run(*args):
    return subprocess.check_output(args, text=True, timeout=5).strip()


def workspace():
    return json.loads(run('hyprctl', 'activeworkspace', '-j'))


def switch(identifier):
    result = run('hyprctl', 'dispatch', 'hl.dsp.focus({ workspace = "' + str(identifier) + '" })')
    if result != 'ok':
        raise RuntimeError(result)


original = workspace()
status = json.loads(run('omarchy-shell', 'notification-center', 'status'))
if status['opened'] or status['progress'] != 0:
    raise SystemExit('Close the notification center before running this check.')
available = json.loads(run('hyprctl', 'workspaces', '-j'))
target = next((w['id'] for w in available
               if w['monitor'] == original['monitor'] and w['id'] > 0
               and w['id'] != original['id']), None)
if target is None:
    raise SystemExit('Open another regular workspace on this monitor first.')
try:
    run('omarchy-shell', 'notification-center', 'open')
    time.sleep(.35)
    switch(target)
    time.sleep(.35)
    before = workspace()['id']
    run('omarchy-shell', 'notification-center', 'close')
    time.sleep(.5)
    after = workspace()['id']
    print(json.dumps({'original': original['id'], 'target': target, 'before_close': before, 'after_close': after, 'passed': before == after == target}))
    if before != target or after != target:
        raise SystemExit('Closing the drawer changed the selected workspace.')
finally:
    run('omarchy-shell', 'notification-center', 'close')
    switch(original['id'])
