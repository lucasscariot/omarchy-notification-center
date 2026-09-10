#!/usr/bin/python
"""Group Omarchy notifications and persist drawer-specific dismissals."""
import configparser
import fcntl
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)

    def handle_starttag(self, tag, attrs):
        if tag in ('br', 'p', 'div'):
            self.parts.append('\n')


MAX_CLEAR_IDS = 500
MAX_DISMISSED_IDS = 4096
MAX_FILES_PER_DIRECTORY = 200
MAX_FILE_BYTES = 1024 * 1024
MAX_NOTIFICATIONS = 50
MAX_APP_NAME_CHARS = 200
MAX_SUMMARY_CHARS = 1000
MAX_BODY_CHARS = 4000
MAX_URL_CHARS = 8192

STATE = Path.home() / '.local/state/omarchy/notification-center-dismissed.json'
VALID_ID = re.compile(r'^\d+-\d+\.json$')


def dismissed_ids(state=STATE):
    try:
        value = json.loads(state.read_text())
        if not isinstance(value, list):
            return set()
        return {key for key in value if isinstance(key, str) and VALID_ID.fullmatch(key)}
    except (OSError, ValueError):
        return set()


def clear_ids(ids, state=STATE):
    if (not isinstance(ids, list) or len(ids) > MAX_CLEAR_IDS
            or any(not isinstance(i, str) or not VALID_ID.fullmatch(i) for i in ids)):
        raise ValueError('Invalid notification identifiers')
    state.parent.mkdir(parents=True, exist_ok=True)
    with state.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        cleared = sorted(
            dismissed_ids(state) | set(ids), key=lambda i: int(i.split('-')[0])
        )[-MAX_DISMISSED_IDS:]
        fd, temporary = tempfile.mkstemp(prefix='.notification-center-', dir=state.parent)
        try:
            with os.fdopen(fd, 'w') as output:
                json.dump(cleared, output)
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, state)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def desktop_apps():
    apps = {}
    data_dirs = os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share')
    data_home = os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))
    locations = [Path(p) / 'applications' for p in data_dirs.split(':')]
    locations.append(Path(data_home) / 'applications')
    for folder in locations:
        for path in folder.glob('*.desktop'):
            try:
                parser = configparser.ConfigParser(interpolation=None, strict=False)
                parser.read(path, encoding='utf-8')
                entry = parser['Desktop Entry']
                name, icon = entry.get('Name', path.stem), entry.get('Icon', '')
                schemes = [
                    mime.removeprefix('x-scheme-handler/')
                    for mime in entry.get('MimeType', '').split(';')
                    if mime.startswith('x-scheme-handler/')
                ]
                aliases = [name, path.stem, entry.get('StartupWMClass', '')]
                app = {
                    'key': path.stem.casefold(), 'desktopId': path.stem,
                    'name': name, 'icon': icon, 'aliases': aliases, 'schemes': schemes,
                }
                for alias in aliases:
                    if alias:
                        apps[alias.casefold()] = app
            except (OSError, ValueError, KeyError, configparser.Error):
                continue
    return apps


def destination(row, desktop):
    """Use explicit supported notification links, never arbitrary command hints."""
    candidates = [row.get('deepLink'), row.get('url')]
    try:
        argv = json.loads(row.get('execArgv') or 'null')
        if isinstance(argv, list) and all(isinstance(v, str) for v in argv):
            if len(argv) == 2 and Path(argv[0]).name == 'xdg-open':
                candidates.append(argv[1])
            if len(argv) == 3 and Path(argv[0]).name == 'gio' and argv[1] == 'open':
                candidates.append(argv[2])
    except (ValueError, TypeError):
        pass
    for value in candidates:
        if (not isinstance(value, str) or len(value) > MAX_URL_CHARS
                or any(ord(c) < 32 for c in value)):
            continue
        try:
            url = urlsplit(value)
        except ValueError:
            continue
        if url.scheme in ('http', 'https') and url.hostname and not url.username and not url.password:
            return value
        if url.scheme and url.scheme not in ('file', 'javascript', 'data', 'shell') and url.scheme in desktop.get('schemes', []):
            return value
    return ''


def normalize_notification(identifier, row, apps):
    """Convert one stored notification to the plain-text drawer contract."""
    plain = PlainText()
    plain.feed(str(row.get('body', '')))
    timestamp = float(row.get('timestamp', 0))
    if not math.isfinite(timestamp):
        return None
    name = str(row.get('app') or '').strip()
    if name.casefold() in ('', 'notify-send') and str(row.get('summary', '')).casefold() in apps:
        name = str(row['summary'])
    if name == 'omarchy-action':
        name = 'Omarchy'
    name = name or 'Notifications'
    desktop = apps.get(name.casefold(), {})
    return dict(
        id=identifier,
        app=desktop.get('name', name)[:MAX_APP_NAME_CHARS],
        appKey=desktop.get('key', name.casefold()),
        icon=desktop.get('icon') or str(row.get('appIcon') or ''),
        desktopId=desktop.get('desktopId', ''),
        aliases=desktop.get('aliases', [name]),
        destination=destination(row, desktop),
        summary=str(row.get('summary', ''))[:MAX_SUMMARY_CHARS],
        body=''.join(plain.parts)[:MAX_BODY_CHARS],
        timestamp=timestamp,
    )


def read_history(base=None, state=STATE, apps=None):
    base = base or Path.home() / '.local/state/omarchy/notifications'
    cleared = dismissed_ids(state)
    apps = desktop_apps() if apps is None else apps
    rows = {}
    for folder in (base / 'history', base):
        for path in list(folder.glob('*.json'))[:MAX_FILES_PER_DIRECTORY]:
            try:
                if not VALID_ID.fullmatch(path.name) or path.name in cleared:
                    continue
                if path.stat().st_size > MAX_FILE_BYTES:
                    continue
                row = json.loads(path.read_text())
                if not isinstance(row, dict):
                    continue
                normalized = normalize_notification(path.name, row, apps)
                if normalized is not None:
                    rows[path.name] = normalized
            except (OSError, ValueError, TypeError):
                continue
    return group_notifications(rows.values())


def group_notifications(rows):
    """Keep newest notifications first and preserve that order across apps."""
    groups = {}
    for row in sorted(rows, key=lambda row: row['timestamp'], reverse=True)[:MAX_NOTIFICATIONS]:
        group = groups.setdefault(row['appKey'], dict(key=row['appKey'], app=row['app'], icon=row['icon'], items=[]))
        if not group['icon'] and row['icon']:
            group['icon'] = row['icon']
        group['items'].append(row)
    return list(groups.values())


def activate(identifier, groups):
    row = next((item for group in groups for item in group['items'] if item['id'] == identifier), None)
    if row is None:
        return {'ok': False, 'error': 'This notification is no longer available.'}
    if row['destination']:
        subprocess.Popen(['/usr/bin/xdg-open', row['destination']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {'ok': True, 'action': 'link'}
    aliases = {name.casefold() for name in row['aliases'] + [row['app']] if name}
    try:
        result = subprocess.run(['hyprctl', 'clients', '-j'], capture_output=True, text=True, timeout=3, check=True)
        clients = json.loads(result.stdout)
        matches = [client for client in clients if any(str(client.get(key, '')).casefold() in aliases for key in ('class', 'initialClass'))]
        if not matches:
            matches = [client for client in clients if client.get('initialClass') == 'org.omarchy.agent' and
                       any(alias in str(client.get('initialTitle', '')).casefold() for alias in aliases)]
        if matches:
            client = min(matches, key=lambda c: c.get('focusHistoryID', 9999) if c.get('focusHistoryID', -1) >= 0 else 9999)
            address = client.get('address', '')
            if re.fullmatch(r'0x[0-9a-fA-F]+', address):
                result = subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.focus({ window = "address:' + address + '" })'],
                                        capture_output=True, timeout=3)
                if result.returncode == 0:
                    return {'ok': True, 'action': 'focus'}
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    if row['desktopId']:
        subprocess.Popen(['/usr/bin/gtk-launch', row['desktopId']], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {'ok': True, 'action': 'launch'}
    if row['app'] == 'Omarchy':
        subprocess.Popen(['omarchy-menu', 'toggle', 'root'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {'ok': True, 'action': 'launch'}
    return {'ok': False, 'error': 'Could not find ' + row['app'] + '. Open it once and try again.'}


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--clear':
        clear_ids(json.loads(sys.argv[2]))
    elif len(sys.argv) == 3 and sys.argv[1] == '--activate':
        print(json.dumps(activate(sys.argv[2], read_history())))
        raise SystemExit(0)
    elif len(sys.argv) != 1:
        raise SystemExit('Usage: read_history.py [--clear JSON_IDS | --activate ID]')
    print(json.dumps(read_history(), allow_nan=False))
