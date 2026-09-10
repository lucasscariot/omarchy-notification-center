"""Load the real Quickshell notification store against a temporary, synthetic backend."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


PROJECT = Path(__file__).resolve().parents[1]

SHELL = '''import QtQuick
import Quickshell
import "plugin"

ShellRoot {
    NotificationStore {
        id: store
        onActivationFailed: {
            if (errorMessage !== "Synthetic activation failure")
                throw new Error("Activation error was not propagated");
            console.log("PASS: runtime store");
            Qt.quit();
        }
    }
    Timer {
        property int phase: 0
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (phase === 0) {
                store.refresh();
                phase = 1;
            } else if (phase === 1 && store.count === 2) {
                store.clearItems(["10-1.json"]);
                store.clearItems(["20-1.json"]);
                if (store.count !== 0)
                    throw new Error("Optimistic clear failed");
                phase = 2;
            } else if (phase === 2 && store.count === 1 && store.errorMessage) {
                // The second clear failed; only that item must be restored.
                if (store.notifications[0].items[0].id !== "20-1.json")
                    throw new Error("Clear rollback restored the wrong item");
                store.activate({id: "20-1.json"});
                phase = 3;
            }
        }
    }
}
'''

BACKEND = '''import json
from pathlib import Path
import sys

log = Path(__file__).with_name("calls.jsonl")
with log.open("a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
if sys.argv[1:2] == ["--activate"]:
    print(json.dumps({"ok": False, "error": "Synthetic activation failure"}))
    raise SystemExit(0)
if sys.argv[1:2] == ["--clear"] and "20-1.json" in json.loads(sys.argv[2]):
    raise SystemExit(1)
print(json.dumps([{"key": "test", "app": "Test", "icon": "", "items": [
    {"id": "10-1.json", "timestamp": 0, "summary": "One", "body": ""},
    {"id": "20-1.json", "timestamp": 1, "summary": "Two", "body": ""}
]}]))
'''


def main():
    # Spaces exercise conversion of Qt file URLs into subprocess paths.
    with tempfile.TemporaryDirectory(prefix="notification center runtime ") as directory:
        root = Path(directory)
        plugin = root / 'plugin'
        (plugin / 'backend').mkdir(parents=True)
        for pattern in ('*.qml', '*.js'):
            for source in PROJECT.glob(pattern):
                shutil.copy2(source, plugin / source.name)
        shutil.copytree(PROJECT / 'tests/imports/qs/Commons', root / 'Commons')
        (plugin / 'backend/read_history.py').write_text(BACKEND)
        (root / 'shell.qml').write_text(SHELL)
        runtime = root / 'runtime'
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                   QT_QUICK_CONTROLS_STYLE='Basic', XDG_RUNTIME_DIR=str(runtime))
        result = subprocess.run(
            ['quickshell', '--no-color', '-p', str(root / 'shell.qml')],
            env=env, capture_output=True, text=True, timeout=15,
        )
        output = result.stdout + result.stderr
        print(output, end='')
        if result.returncode or 'PASS: runtime store' not in output:
            raise SystemExit('Quickshell runtime smoke test failed')
        calls = [json.loads(line) for line in
                 (plugin / 'backend/calls.jsonl').read_text().splitlines()]
        clears = [json.loads(args[1]) for args in calls if args[:1] == ['--clear']]
        assert clears == [['10-1.json'], ['20-1.json']], calls
        assert ['--activate', '20-1.json'] in calls, calls


if __name__ == '__main__':
    main()
