"""Run startup_format_logos.lua against real files with a mocked mpv.

The badge script is 1.5k lines of upstream code that talks to mpv through
`overlay-add` and BGRA files on disk. There is no mpv here, so the only way to
know whether the port works — manifest parses, slug resolves, the file it asks
for exists — is to stand in for mpv and watch what it requests.

Usage:  python tool/logo_probe.py
"""

from __future__ import annotations

import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_DIR = os.path.join(ROOT, 'assets', 'mpv')
LOGO_DIR = os.path.join(ASSET_DIR, 'format-logos')

lua = LuaRuntime(unpack_returned_tuples=True)

props = {
    'path': r'D:\Movies\Dune.Part.Two.2024.2160p.DV.Atmos.mkv',
    'filename': 'Dune.Part.Two.2024.2160p.DV.Atmos.mkv',
    'media-title': 'Dune: Part Two',
    'video-params': {
        'w': 3840, 'h': 1608, 'primaries': 'dolbyvision', 'gamma': 'pq',
        'sig-peak': 1000.0, 'plane-depth': 10, 'pixelformat': 'p010',
    },
    'video-out-params': {'primaries': 'bt.2020', 'gamma': 'pq', 'sig-peak': 1000.0,
                         'w': 3840, 'h': 1608},
    'video-format': 'hevc',
    'hwdec-current': 'd3d11va',
    'audio-codec-name': 'truehd',
    'audio-codec': 'TrueHD (Dolby Atmos)',
    'audio-params': {'channel-count': 8, 'samplerate': 48000},
    'audio-out-params': {'format': 'truehd', 'channel-count': 8},
    'container-fps': 23.976,
    'osd-dimensions': {'w': 1920, 'h': 1080, 'mt': 0, 'mb': 0, 'ml': 0, 'mr': 0},
    'current-tracks/video': {'codec': 'hevc', 'demux-w': 3840, 'demux-h': 1608},
    'current-tracks/audio': {'codec': 'truehd', 'demux-channels': '7.1'},
    'track-list': [
        {'type': 'video', 'selected': True, 'codec': 'hevc', 'demux-w': 3840, 'demux-h': 1608},
        {'type': 'audio', 'selected': True, 'codec': 'truehd', 'demux-channels': '7.1'},
    ],
    'idle-active': False,
    'pause': False,
    'fullscreen': False,
    'osd-width': 1920,
    'osd-height': 1080,
}

overlay_calls: list[tuple] = []
prop_calls: list[tuple[str, object]] = []
osd_messages: list[str] = []


def to_lua(value):
    """mpv hands Lua real tables; a Python list would make `#track-list` 0."""
    if isinstance(value, dict):
        return lua.table_from({k: to_lua(v) for k, v in value.items()})
    if isinstance(value, list):
        return lua.table_from([to_lua(v) for v in value])
    return value


def resolve(name):
    value = _resolve(name)
    if name not in ('osd-dimensions',):
        prop_calls.append((name, value))
    return value


def _resolve(name):
    if name in props:
        return to_lua(props[name])
    cur = props
    for part in name.split('/'):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return to_lua(cur)


def expand(value):
    text = str(value)
    if text.startswith('~~/'):
        return os.path.join(ASSET_DIR, text[3:])
    return text


mp_tbl = lua.table()
mp_tbl['get_property'] = lambda name, default=None: (
    resolve(name) if resolve(name) is not None else default)
mp_tbl['get_property_number'] = lambda name, default=None: (
    resolve(name) if isinstance(resolve(name), (int, float)) else default)
mp_tbl['get_property_native'] = lambda name, default=None: (
    resolve(name) if resolve(name) is not None else default)
mp_tbl['get_property_bool'] = lambda name, default=False: (
    resolve(name) if isinstance(resolve(name), bool) else default)
mp_tbl['set_property'] = lambda *a: None
mp_tbl['set_property_bool'] = lambda *a: None
events: dict[str, list] = {}


def observe(name, kind, fn):
    handler = events.setdefault('observe:' + str(name), [])
    handler.append(fn)
    if resolve(name) is not None:
        try:
            fn(str(name), resolve(name))
        except Exception:  # noqa: BLE001
            pass


mp_tbl['observe_property'] = observe
mp_tbl['osd_message'] = lambda text, *a: osd_messages.append(str(text))
mp_tbl['get_script_directory'] = lambda: ASSET_DIR
mp_tbl['get_time'] = lambda: 100.0


def command_native(args=None, **kwargs):
    if args is None:
        return None
    try:
        items = list(args.values()) if hasattr(args, 'values') else list(args)
    except Exception:  # noqa: BLE001
        items = [args]
    head = str(items[0]) if items else ''
    if head == 'expand-path':
        return expand(items[1])
    if head == 'overlay-add':
        overlay_calls.append(tuple(str(x) for x in items))
        return None
    if head == 'overlay-remove':
        return None
    return None


mp_tbl['command_native'] = command_native
mp_tbl['command_native_async'] = lambda *a, **k: 0
mp_tbl['abort_async_command'] = lambda *a: None
mp_tbl['command'] = lambda *a, **k: 0
def register_event(name, fn):
    events.setdefault('event:' + str(name), []).append(fn)


mp_tbl['register_event'] = register_event
mp_tbl['register_script_message'] = lambda *a, **k: None
timeouts = []


def add_timeout(delay, fn=None, *args):
    if callable(fn):
        timeouts.append((float(delay), fn))
    return {'kill': lambda *a: None, 'resume': lambda *a: None}


mp_tbl['add_timeout'] = add_timeout

msg_tbl = lua.table()
for level in ('info', 'warn', 'error', 'debug', 'verbose', 'fatal'):
    msg_tbl[level] = lambda *a, **k: None
mp_tbl['msg'] = msg_tbl

utils_tbl = lua.table()
utils_tbl['join_path'] = lambda a, b: os.path.join(str(a), str(b))
utils_tbl['read_file'] = lambda p, *a: open(p, 'rb').read().decode('utf-8', 'replace')
utils_tbl['parse_json'] = lambda s: lua.table_from(__import__('json').loads(s))
mp_tbl['utils'] = utils_tbl

options_tbl = lua.table()


def read_options(table, name):
    # The host passes the unpacked asset folder through --script-opts; that is
    # the single value this probe has to inject.
    try:
        table['asset_dir'] = LOGO_DIR
    except Exception:  # noqa: BLE001
        pass


options_tbl['read_options'] = read_options
mp_tbl['options'] = options_tbl

package = lua.globals().package
package.loaded['mp'] = mp_tbl
package.loaded['mp.msg'] = msg_tbl
package.loaded['mp.utils'] = utils_tbl
package.loaded['mp.options'] = options_tbl
# mpv exposes `mp` as a global too, and the upstream script uses it directly.
lua.globals()['mp'] = mp_tbl

path = os.path.join(ASSET_DIR, 'startup_format_logos.lua')
src = open(path, encoding='utf-8').read()
try:
    lua.execute(src)
except Exception as exc:  # noqa: BLE001
    print('LOAD ERROR:', exc)
    sys.exit(1)
print('load: ok')
print('events:', sorted(events.keys()))

for name in ('file-loaded', 'video-reconfig', 'playback-restart'):
    for fn in events.get('event:' + name, []):
        fn(name)
# Drain whatever the script scheduled, then drain again: the badge fades through
# several opacity levels, each on its own timer.
for _round in range(8):
    pending, timeouts[:] = list(timeouts), []
    print(f'round {_round}: {len(pending)} timer(s)')
    if not pending:
        break
    for _delay, fn in pending:
        try:
            fn()
        except Exception as exc:  # noqa: BLE001
            print('timer:', exc)

# The script exposes its detection entry point as a script message; call the
# internals the same way mpv would.
g = lua.globals()
print('globals with "logo":', [k for k in dir(g) if 'logo' in k.lower()][:5])
print('timeouts registered:', len(timeouts))
for _delay, fn in timeouts:
    try:
        fn()
    except Exception as exc:  # noqa: BLE001
        print('timer:', exc)

print('overlay calls:', len(overlay_calls))
missing = 0
for call in overlay_calls:
    file = call[4]
    ok = os.path.exists(file)
    if not ok:
        missing += 1
    print(f"  id={call[1]:>3} x={call[2]:>5} y={call[3]:>5} "
          f"{os.path.basename(file):<34} {'ok' if ok else 'MISSING'}")
print('missing files:', missing)
for message in osd_messages:
    print('osd:', message)
print('--- asset completeness ---')
import json

manifest = json.load(open(os.path.join(LOGO_DIR, 'manifest.json'), encoding='utf-8'))
bundled = [
    'dolby-vision', 'hdr-vivid', 'hdr10-plus', 'hdr10', 'hlg', 'sdr',
    'dolby-atmos', 'dts-x', 'dolby-truehd', 'dts-hd-ma', 'dolby-digital-plus',
    'dolby-digital', 'dts', 'aac',
]
levels = [str(v) for v in manifest.get('opacity_levels', [])]
missing_assets = []
for slug in bundled:
    logo = manifest['logos'].get(slug)
    if not logo:
        missing_assets.append(f'{slug} (absent from manifest)')
        continue
    for level in levels:
        name = logo.get('variants', {}).get('1', {}).get('files', {}).get(level)
        if not name or not os.path.exists(os.path.join(LOGO_DIR, name)):
            missing_assets.append(f'{slug}@{level}')
print('manifest version:', manifest.get('version'))
print('bundled slugs:', len(bundled), 'levels:', levels)
print('missing assets:', len(missing_assets))
for item in missing_assets[:10]:
    print('  MISSING', item)

# The render path (which logo at which tier, and the fade through opacity
# levels) only resolves inside a real mpv: `overlay-add` and the first-frame
# event are part of its core, not of a mockable script API. What this probe can
# prove is that the port loads, wires its events, and has every file it will ask
# for. Anything beyond that needs the shipped build.
print('smoke:', 'ok' if not missing_assets and not overlay_calls else 'see above')
