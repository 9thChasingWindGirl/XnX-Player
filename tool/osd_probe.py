"""Run player_osd.lua under a mock mpv and dump what it actually draws.

No mpv here, so this stubs the API surface the script touches and prints the
ASS payload handed to osd-overlay. That is enough to tell "the script draws
nothing" apart from "mpv draws it and the user cannot see it".
"""
import sys
import lupa
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)

props = {
    'duration': 5400.0,
    'time-pos': 120.0,
    'pause': False,
    'track-list': [
        {'type': 'video', 'selected': True, 'codec': 'hevc', 'demux-w': 3840,
         'demux-h': 1608, 'demux-fps': 23.976, 'hwdec-current': 'd3d11va'},
        {'type': 'audio', 'selected': True, 'codec': 'eac3', 'lang': 'eng',
         'demux-channels': '5.1', 'title': 'English 5.1'},
        {'type': 'sub', 'selected': True, 'codec': 'hdmv_pgs_subtitle', 'lang': 'chi'},
    ],
    'video-params': {'w': 3840, 'h': 1608, 'pixelformat': 'd3d11', 'colormatrix': 'bt.2020-ncl',
                     'primaries': 'bt.2020', 'gamma': 'pq', 'sig-peak': 1000.0, 'average-bpp': 40.0},
    # What the video output settled on. Equal to the source here, which is what
    # "HDR really got through" looks like; the badges dim when it does not.
    'video-out-params': {'primaries': 'bt.2020', 'gamma': 'pq', 'sig-peak': 1000.0},
    'audio-codec': 'E-AC-3 (Dolby Digital Plus)',
    'video-format': 'hevc',
    'container-fps': 23.976,
    'hwdec-current': 'd3d11va',
    'video-bitrate': 62000000.0,
    'audio-codec-name': 'eac3',
    'audio-params': {'channel-count': 6, 'samplerate': 48000},
    'osd-dimensions': {'w': 3440, 'h': 1440, 'mt': 0, 'mb': 0, 'ml': 1, 'mr': 1},
    'chapter-list': [
        {'title': 'Chapter 1', 'time': 0.0},
        {'title': 'Chapter 2', 'time': 600.0},
    ],
    'chapters': 2,
    'chapter': 0,
    'media-title': 'Dune.Part.Two.2024.2160p',
    'filename': 'Dune.Part.Two.2024.2160p.mkv',
    'path': 'Dune.Part.Two.2024.2160p.mkv',
    'playlist': [{'filename': 'a.mkv', 'current': True}],
    'playlist-pos': 0,
    'playlist-count': 1,
    'user-data/player/title': 'Dune: Part Two',
    'user-data/player/skip-intro': 'yes',
    'speed': 1.0,
    'aid': '1',
    'sid': '1',
    'volume': 100.0,
    'mute': False,
    'seekable': True,
    'idle-active': False,
    'cache-buffering-state': 100.0,
    'demuxer-cache-time': 300.0,
}

overlays = []


def make_overlay(fmt):
    # A pure Lua table, not a Python dict: `osd:update()` on a Python object
    # crosses the lupa boundary and produced a bogus "'dict' object is not
    # callable" from inside render(), which looks exactly like a script bug.
    ov = lua.table()
    ov['format'] = fmt
    ov['data'] = ''
    ov['res_x'] = 0
    ov['res_y'] = 0
    ov['z'] = 0
    ov['updates'] = 0
    ov['removes'] = 0
    ov['update'] = lua.eval('function(self) self.updates = self.updates + 1 end')
    ov['remove'] = lua.eval('function(self) self.removes = self.removes + 1 end')
    overlays.append(ov)
    return ov


events = {}
timeouts = []
handlers = {}


def add_timeout(t, fn):
    timeouts.append((t, fn))
    return {'kill': lambda *a: None}


def observe(name, kind, fn):
    handlers.setdefault('observe-' + name, []).append(fn)
    # mpv fires an observer immediately with the current value. Doing the same
    # is what makes `duration`, `media-title` and friends non-empty here, which
    # the preview needs to render a realistic bar.
    if name in props:
        try:
            fn(name, props[name])
        except Exception:  # noqa: BLE001 - the OSD may not exist yet
            pass


mp_tbl = lua.table()


# mpv hands Lua real tables, where a missing key is simply nil. A Python dict
# proxied by lupa is stricter and raises KeyError instead — which showed up as
# bogus "'w'" / "'dict' object is not callable" errors from code that is correct
# on a real player. Convert every nested map up front so the mock behaves like
# the thing it stands in for.
def _to_lua(value):
    if isinstance(value, dict):
        return lua.table_from({k: _to_lua(v) for k, v in value.items()})
    if isinstance(value, list):
        return lua.table_from([_to_lua(v) for v in value])
    return value


props = {k: _to_lua(v) for k, v in props.items()}

_MISSING = object()


def _index(table, part):
    try:
        value = table[part]
    except Exception:  # noqa: BLE001 - a proxy that refuses the key means "absent"
        return _MISSING
    return _MISSING if value is None else value


def resolve(name):
    """mpv offers `video-params/w` as a path into a native map; mirror that."""
    if name in props:
        return props[name]
    cur = props
    for part in name.split('/'):
        nxt = _index(cur, part)
        if nxt is _MISSING:
            return None
        cur = nxt
    return cur


mp_tbl['get_property'] = lambda name, default=None: (
    resolve(name) if resolve(name) is not None else default)
mp_tbl['get_property_number'] = lambda name, default=None: (
    resolve(name) if isinstance(resolve(name), (int, float)) else default)
mp_tbl['get_property_native'] = lambda name, default=None: (
    resolve(name) if resolve(name) is not None else default)
mp_tbl['get_property_bool'] = lambda name, default=False: (
    resolve(name) if isinstance(resolve(name), bool) else default)
mp_tbl['set_property'] = lambda *a: None
mp_tbl['set_property_number'] = lambda *a: None
mp_tbl['set_property_native'] = lambda *a: None
# Record what the script asks mpv to do: the forwarded-pointer path can only be
# verified by watching for the seek / volume / pause command it produces.
commands = []
mp_tbl['commandv'] = lambda *a: commands.append(a)
mp_tbl['command'] = lambda *a: commands.append(a)
mp_tbl['create_osd_overlay'] = make_overlay
mp_tbl['add_timeout'] = add_timeout
periodic = []


def add_periodic(t, fn):
    periodic.append(fn)
    return {'kill': lambda *a: None}


mp_tbl['add_periodic_timer'] = add_periodic
mp_tbl['observe_property'] = observe
mp_tbl['register_event'] = lambda name, fn: events.setdefault(name, []).append(fn)
mp_tbl['register_script_message'] = lambda name, fn: handlers.setdefault('msg-' + name, []).append(fn)
mp_tbl['add_key_binding'] = lambda *a, **k: None
mp_tbl['set_key_bindings'] = lambda *a, **k: None
mp_tbl['enable_key_bindings'] = lambda *a, **k: None
mp_tbl['disable_key_bindings'] = lambda *a, **k: None
# A frozen clock makes every fade-in compute 0 and previews come out
# invisible; advance it on each simulated event instead.
clock = [100.0]
mp_tbl['get_time'] = lambda: clock[0]
mp_tbl['get_script_name'] = lambda: 'player_osd'
mp_tbl['get_script_directory'] = lambda: '.'
mp_tbl['osd_message'] = lambda *a: None

msg_tbl = lua.table()
for level in ('info', 'warn', 'error', 'debug', 'verbose', 'fatal'):
    msg_tbl[level] = lambda *a, **k: None
mp_tbl['msg'] = msg_tbl

utils_tbl = lua.table()
utils_tbl['format_json'] = lambda t: '{}'
def parse_json(s):
    import json as _json
    try:
        return lua.table_from(_json.loads(s))
    except Exception:
        return None


utils_tbl['parse_json'] = parse_json
utils_tbl['join_path'] = lambda a, b: a + '/' + b
utils_tbl['split_path'] = lambda p: ('', p, '')
utils_tbl['read_file'] = lambda *a: None
utils_tbl['write_file'] = lambda *a: None
mp_tbl['utils'] = utils_tbl

package = lua.globals().package
loaded = package.loaded
loaded['mp'] = mp_tbl
loaded['mp.msg'] = msg_tbl
loaded['mp.utils'] = utils_tbl

path = sys.argv[1] if len(sys.argv) > 1 else 'assets/mpv/player_osd.lua'
src = open(path, encoding='utf-8').read()

try:
    lua.execute(src)
except Exception as exc:  # noqa: BLE001 - report and stop
    print('LOAD/RUN ERROR:', exc)
    sys.exit(1)
print('load: ok')

print('overlays created:', len(overlays), 'initial updates:', overlays[0]['updates'],
      'removes:', overlays[0]['removes'])
print('res:', overlays[0]['res_x'], 'x', overlays[0]['res_y'], 'z', overlays[0]['z'])

g = lua.globals()

# Simulate a loaded file, then a mouse move (Flutter sends {"cmd":"show"}).
for fn in events.get('file-loaded', []):
    fn()
for fn in handlers.get('msg-player-cmd', []):
    fn('{"cmd":"show"}')
for fn in periodic:
    fn()


_pcall = lua.eval('''
function(fn, ...)
  local ok, err = xpcall(fn, function(e) return tostring(e) .. "\\n" .. debug.traceback("", 2) end, ...)
  if not ok then return err end
end''')


def send(payload):
    # pcall so a bug surfaces as "player_osd.lua:1234: attempt to ..." instead of
    # a Python traceback in lupa's guts with no Lua line number. The `...` is not
    # optional: `pcall(fn)` alone calls the handler with no payload, which parse
    # as a malformed command and silently does nothing.
    for fn in handlers.get('msg-player-cmd', []):
        err = _pcall(fn, payload)
        if err:
            print('LUA ERROR in player-cmd:', err)
    for fn in periodic:
        err = _pcall(fn)
        if err:
            print('LUA ERROR in timer:', err)


# Every menu, the stats panel and the help sheet draw through different code
# paths; a typo in any of them would only show up on the user's screen.
send('{"cmd":"menu","id":"more"}')
print('menu(more) events:', len(overlays[0]['data'].splitlines()))
send('{"cmd":"key","key":"i"}')
print('stats events:', len(overlays[0]['data'].splitlines()))
send('{"cmd":"key","key":"h"}')
print('help events:', len(overlays[0]['data'].splitlines()))

data = overlays[0]['data']
print('---')
print('data length:', len(data))
print('update count:', overlays[0]['updates'])
print('newline count:', data.count('\n'), 'literal \\N count:', data.count('\\N'))
print('starts with:', repr(data[:180]))
print('---')
print('first 3 segments:')
for seg in data.split('\\N')[:3]:
    print('  ', seg[:140])

# Transport-bar state on its own: this is the view the user stares at, so dump
# it where a human can check the scrim and the badge row by eye.
send('{"cmd":"key","key":"h"}')  # close the help sheet
send('{"cmd":"key","key":"i"}')  # close the stats panel
send('{"cmd":"hide"}')
send('{"cmd":"show"}')
# Fire the deferred callbacks the script registered (the intro cards wait 0.4s
# for the decoder to report). Without this the preview never shows them.
for _t, fn in timeouts:
    try:
        fn()
    except Exception as exc:  # noqa: BLE001 - a stub may be missing
        print('timeout skipped:', exc)
clock[0] += 1.2  # past the intro fade-in, before its fade-out
# One of those timers is the auto-hide; bring the chrome back before dumping.
send('{"cmd":"show"}')
for fn in periodic:
    fn()
chrome = overlays[0]['data'].splitlines()
print('---')
print('chrome events:', len(chrome))
for line in chrome:
    if '\\blur' in line and '\\1c&H000000&' in line:
        print('  scrim:', line[:110])
print('badge pills (text runs at META_Y):')
for line in chrome:
    if 'fs17' in line:
        print('  ', line[line.find('}') + 1:][:40])
open('_osd_chrome.txt', 'w', encoding='utf-8').write(overlays[0]['data'])
print('wrote _osd_chrome.txt')

# ---- forwarded pointer -----------------------------------------------------
#
# mpv never sees the mouse in this embedding, so the only pointer path that can
# matter is `{"cmd":"mouse"}` from Flutter. Exercise it end to end: move onto the
# seekbar, press, drag, release, and check that mpv is actually asked to seek.
print('---')
commands.clear()
bar_y = 884  # BAR_Y in the design space
dim = props['osd-dimensions']
sy = dim['h'] / 1080.0
ny = (bar_y * sy + dim['mt']) / (dim['h'] + dim['mt'] + dim['mb'])

send('{"cmd":"mouse","ev":"move","nx":0.5,"ny":%.5f}' % ny)
send('{"cmd":"mouse","ev":"down","nx":0.5,"ny":%.5f,"button":"left"}' % ny)
print('after press on bar:', commands[-1] if commands else 'NO COMMAND')

commands.clear()
send('{"cmd":"mouse","ev":"move","nx":0.75,"ny":%.5f}' % ny)
print('after drag to 75%:', commands[-1] if commands else 'NO COMMAND')

commands.clear()
send('{"cmd":"mouse","ev":"up","nx":0.75,"ny":%.5f,"button":"left"}' % ny)
print('after release:', commands[-1] if commands else 'NO COMMAND')

commands.clear()
send('{"cmd":"mouse","ev":"move","nx":0.5,"ny":0.5}')
send('{"cmd":"mouse","ev":"wheel","nx":0.5,"ny":0.5,"delta":1}')
print('after wheel up:', commands[-1] if commands else 'NO COMMAND')

# The hover path must highlight the control it is over, otherwise nothing looks
# clickable even though clicking works.
send('{"cmd":"show"}')
hover_note = []
for line in overlays[0]['data'].splitlines():
    if 'fs20' in line or 'fs17' in line:
        hover_note.append(line[line.find('}') + 1:][:18])
print('chrome still renders:', len(overlays[0]['data'].splitlines()), 'events')

# ---- HDR passthrough -------------------------------------------------------
#
# The chrome is SDR content while the swapchain is PQ, so the script has to
# thicken the outline and densify the scrim the moment `video-target-params`
# says the output is real HDR. Nothing else in this file exercises that branch,
# and it is the kind of change that breaks silently: the OSD still draws, it
# just goes back to reading grey over an HDR picture.
print('---')
for fn in handlers.get('observe-video-target-params', []):
    fn('video-target-params', _to_lua({'gamma': 'pq', 'max-luma': 1000}))
for fn in periodic:
    fn()
hdr_lines = overlays[0]['data'].splitlines()
scrims = [line for line in hdr_lines if '\\blur' in line and '\\1c&H000000&' in line]
for line in scrims:
    print('  hdr scrim:', line[:110])
bordered = [line for line in hdr_lines if '\\bord2.4' in line]
print('hdr text with the heavy outline:', len(bordered))
