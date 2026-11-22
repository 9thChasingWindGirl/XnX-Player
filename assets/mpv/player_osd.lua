--[[
  XnX Player — in-player UI
  ---------------------------------------------------------------------------
  mpv paints the video into a native child window that always sits above the
  Flutter canvas, so the entire in-player UI has to live inside mpv. This
  script draws it as an ASS overlay in a fixed 1920x1080 coordinate space and
  owns every playback action, mirroring the Yaozhi reference build:

    · bottom bar      play / seek / time / track menus / speed / stats
    · progress        buffer, chapter ticks, hover scrub, intro/outro markers
    · menus           audio, subtitle, chapters, speed, playlist, video,
                      stats, more  (keyboard + mouse, PS5 focus style)
    · badges          decode, resolution, codec, HDR, bitrate — like the
                      reference build's progress-bar media labels
    · segments        opening/ending auto-skip, manual marks, persisted JSON
    · toasts          volume, seek, speed, track switches

  Sections: CONST / ASS / STATE / FORMAT / MENUS / RENDER / SEGMENTS / INPUT /
  MOUSE / IPC / LIFECYCLE
--]]

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

-- ==== CONST ================================================================

local W, H = 1920, 1080
local SAFE = 96
local RIGHT = W - SAFE

local TITLE_Y = 770
local META_Y = 844
local BAR_Y = 884
local BAR_H = 3
local CTRL_Y = 902
local CTRL_H = 66
local HINT_Y = 992
local MENU_BOTTOM = 862
-- Narrower and taller than before: 600 was half a 1088 px window and 52 put
-- the rows at 29 px, so the panel read as a wall of tiny text next to the
-- Dart-drawn transport. It now uses the same rhythm as that chrome.
local MENU_W = 520
local ROW_H = 60
local AUTOHIDE = 4.5
local TICK = 0.1

local WHITE = '&HFFFFFF&'
local GREY = '&HBEBEBE&'
local DIM = '&H8C8C8C&'
local BLACK = '&H000000&'

-- Format-badge accents. ASS colours are &HBBGGRR&, not RGB.
local HDR_GOLD = '&H3CBEFF&' -- RGB 255,190,60
local DV_PURPLE = '&HFF78A0&' -- RGB 160,120,255
local HLG_CYAN = '&HDCDC50&' -- RGB 80,220,220
local DTS_AMBER = '&H4696FF&' -- RGB 255,150,70

-- Timeline band tints. A cut and a mute are different promises: one removes
-- picture, the other only sound. Drawing both in the same white — separated by
-- two steps of alpha — meant the only way to tell them apart was to hover the
-- bar and read a tooltip. The reference build gives EDL its own red row above
-- the progress bar for the same reason; here the cut row is red and the mute
-- row stays a faint white hairline beneath it.
local CUT_TINT = '&H576BFF&' -- RGB 255,107,87
local OK_GREEN = '&H72D96E&' -- RGB 110,217,114

-- Bookmark ticks. Gold, because it is the one hue on the bar that is not a
-- judgement about the file: a cut is bad news, a bookmark is an annotation.
-- Kept as its own constant rather than reusing the HDR badge gold so the two
-- can diverge without one silently recolouring the other.
local BOOKMARK_TINT = '&H3CBEFF&' -- RGB 255,190,60

local FONT = 'Microsoft YaHei UI'
local MONO = 'Consolas'

-- ==== ASS ==================================================================

local function esc(s)
  s = tostring(s or '')
  s = s:gsub('[{}]', '')
  s = s:gsub('[\r\n\t]+', ' ')
  return s
end

local function round(v)
  v = tonumber(v) or 0
  if v < 0 then
    return math.ceil(v - 0.5)
  end
  return math.floor(v + 0.5)
end

--- UTF-8 aware truncation; returns at most `max_chars` characters.
local function clip(s, max_chars)
  s = s or ''
  local n, i = 0, 1
  while i <= #s do
    local c = s:byte(i)
    local step = 1
    if c >= 240 then
      step = 4
    elseif c >= 224 then
      step = 3
    elseif c >= 192 then
      step = 2
    end
    n = n + 1
    if n > max_chars then
      return s:sub(1, i - 1) .. '…'
    end
    i = i + step
  end
  return s
end

--- Rough advance width: CJK glyphs are ~1em, Latin ~0.55em.
local function measure(s, size)
  s = s or ''
  local w, i = 0, 1
  while i <= #s do
    local c = s:byte(i)
    local step = 1
    if c >= 240 then
      step = 4
    elseif c >= 224 then
      step = 3
    elseif c >= 192 then
      step = 2
    end
    if step >= 3 then
      w = w + size
    else
      w = w + size * 0.56
    end
    i = i + step
  end
  return w
end

local function rrect_path(w, h, r)
  if w <= 0 or h <= 0 then
    return ''
  end
  if r <= 0.5 then
    return string.format('m 0 0 l %d 0 %d %d 0 %d', round(w), round(w), round(h), round(h))
  end
  r = math.min(r, w / 2, h / 2)
  local d = r * 0.4477153
  return table.concat({
    'm ' .. round(r) .. ' 0',
    'l ' .. round(w - r) .. ' 0',
    'b ' .. round(w - d) .. ' 0 ' .. round(w) .. ' ' .. round(r - d) .. ' ' .. round(w) .. ' ' .. round(r),
    'l ' .. round(w) .. ' ' .. round(h - r),
    'b ' .. round(w) .. ' ' .. round(h - r + d) .. ' ' .. round(w - r + d) .. ' ' .. round(h) .. ' '
        .. round(w - r) .. ' ' .. round(h),
    'l ' .. round(r) .. ' ' .. round(h),
    'b ' .. round(r - d) .. ' ' .. round(h) .. ' 0 ' .. round(h - r + d) .. ' 0 ' .. round(h - r),
    'l 0 ' .. round(r),
    'b 0 ' .. round(r - d) .. ' ' .. round(r - d) .. ' 0 ' .. round(r) .. ' 0',
  }, ' ')
end

-- `alpha` here is an OPACITY, 0x00 = invisible, 0xFF = solid, which is the
-- opposite of ASS's \1a tag. Inverting it once here keeps every call site
-- readable and stops the classic "I asked for a translucent panel and got a
-- solid white block" mistake.
-- `blur` (optional) feathers the shape with libass' gaussian. One feathered
-- plate is the only way to build a gradient here: ASS has no gradient fill, and
-- stacking flat rectangles in equal steps leaves a visible seam every step,
-- which on high-contrast footage reads as stripes across the bottom bar.
local function rect(x, y, w, h, r, color, alpha, blur)
  if w <= 0 or h <= 0 then
    return ''
  end
  local opacity = 0xFF - math.max(0, math.min(0xFF, round(alpha or 0)))
  local soft = (blur and blur > 0) and string.format('\\blur%.1f', blur) or '\\blur0'
  return string.format(
    '{\\an7\\pos(%d,%d)\\p1\\bord0\\shad0%s\\1c%s\\1a&H%02X&}%s{\\p0}',
    round(x), round(y), soft, color, opacity, rrect_path(w, h, r)
  )
end

-- Stroke-only rectangle: transparent fill, coloured 1px border. Used for badges
-- that the pipeline is *not* delivering, so "dim outline" and "lit pill" can sit
-- in the same row without the dim ones reading as broken.
local function rect_line(x, y, w, h, r, color, alpha, width)
  if w <= 0 or h <= 0 then
    return ''
  end
  local a = 0xFF - math.max(0, math.min(0xFF, round(alpha or 0xFF)))
  return string.format(
    '{\\an7\\pos(%d,%d)\\p1\\bord%.1f\\shad0\\1a&HFF&\\3c%s\\3a&H%02X&}%s{\\p0}',
    round(x), round(y), width or 1.3, color, a, rrect_path(w, h, r)
  )
end

local function triangle(x, y, s, dir, color, alpha)
  local opacity = 0xFF - math.max(0, math.min(0xFF, round(alpha or 0)))
  local path
  if dir == 'left' then
    path = string.format('m %d 0 l 0 %d %d %d', round(s), round(s / 2), round(s), round(s))
  else
    path = string.format('m 0 0 l %d %d 0 %d', round(s), round(s / 2), round(s))
  end
  return string.format(
    '{\\an7\\pos(%d,%d)\\p1\\bord0\\shad0\\1c%s\\1a&H%02X&}%s{\\p0}',
    round(x), round(y), color, opacity, path
  )
end

-- align: 7 = top-left, 9 = top-right, 5 = top-center, 8 = top-middle-center
--- Weight of the OSD's black outline, and how hard the scrim is allowed to be.
---
--- These are declared once and rewritten by [set_output_space] because the same
--- pixels have to survive two very different colour pipelines.
---
--- SDR is the easy case: a hairline outline is enough, the way uosc does it.
---
--- HDR passthrough is not. Everything this script draws is SDR content that mpv
--- maps into PQ, so its white lands on the SDR reference (≈203 cd/m²) while the
--- picture around it can reach 1000+. Type cannot be made brighter than white,
--- and mpv offers no option to exempt the OSD from that conversion (gpu-next
--- adapts every SDR bitmap to the swapchain's colour space). The first attempt
--- went the other way — heavier scrims and shadows — and the user reported the
--- chrome getting *darker*: PQ already reads greys low, so extra ink compounds
--- the loss. The working compensation is the opposite: thinner scrims (PQ black
--- sits deeper, so less dimming is needed), no drop shadow, secondary text
--- brightened toward full white, and the outline kept heavy for contrast.
local TEXT_BORDER = 1.2
local TEXT_SHADOW = 0
local TEXT_SHADOW_ALPHA = 0x30
local SCRIM_TOP = 0x4E
local SCRIM_BOTTOM = 0x62

--- Whether the output is really emitting PQ/HLG. Lives here — above [text] and
--- ahead of `state` — because [text] reads it on every draw.
local HDR_OUTPUT = false

--- Draws one line of text.
---
--- A hairline black outline is always on, the way uosc does it: the reference
--- build has no gradient scrim at all and relies on `text_border` so white type
--- stays readable over a bright frame. Without it, dropping the scrim would
--- make the bar unreadable on a snowy or desert shot.
local function text(x, y, size, color, alpha, str, align, bold, font)
  -- PQ passthrough renders secondary text (alpha < 255) dimmer than the same
  -- pixel in SDR: the sRGB→PQ ramp compresses mid-tones. Lifting alpha toward
  -- full white partially restores the intended hierarchy.
  if HDR_OUTPUT and alpha < 255 then
    alpha = math.min(255, alpha + (255 - alpha) * 0.3)
  end
  return string.format(
    '{\\an%d\\pos(%d,%d)\\fn%s\\fs%d\\bord%.1f\\shad%.1f\\3c&H000000&\\3a&H88&'
      .. '\\4c&H000000&\\4a&H%02X&\\%s\\c%s\\1a&H%02X&}%s',
    align or 7, round(x), round(y), font or FONT, round(size),
    TEXT_BORDER, TEXT_SHADOW, TEXT_SHADOW_ALPHA,
    bold and 'b1' or 'b0', color, round(alpha), esc(str)
  )
end

local function fmt_time(t)
  t = math.max(0, math.floor(tonumber(t) or 0))
  local h = math.floor(t / 3600)
  local m = math.floor((t % 3600) / 60)
  local s = t % 60
  if h > 0 then
    return string.format('%d:%02d:%02d', h, m, s)
  end
  return string.format('%02d:%02d', m, s)
end

local function fmt_bytes(v)
  v = tonumber(v) or 0
  if v <= 0 then
    return '—'
  end
  local units = { 'B', 'KiB', 'MiB', 'GiB', 'TiB' }
  local i = 1
  while v >= 1024 and i < #units do
    v = v / 1024
    i = i + 1
  end
  if i == 1 then
    return string.format('%.0f %s', v, units[i])
  end
  return string.format('%.1f %s', v, units[i])
end

local function fmt_rate(v)
  v = tonumber(v) or 0
  if v <= 0 then
    return '—'
  end
  return string.format('%.1f Mbps', v / 1000000)
end

-- ==== STATE ================================================================

local state = {
  visible = false,
  paused = false,
  position = 0,
  duration = 0,
  buffer = 0,
  title = '',
  fallback_title = '',
  chapters = {},
  chapter = -1,
  -- Bookmarks for the current file, read from the per-file record on load.
  -- Kept on `state` because the bar redraws many times a second and reading a
  -- file from a paint path would be a stall, not a feature.
  bookmarks = {},
  hover = nil,
  pointer = nil,
  menu = nil,
  stats = false,
  help = false,
  toast = nil,
  mouse_seen = false,
  -- True once the host starts forwarding pointer events. mpv's own `mouse-pos`
  -- never updates in this embedding, so this flag is what tells the observer
  -- to stop waiting for something that will never arrive.
  external_pointer = false,
  mouse_events = 0,
  audio_mode = false,
  -- True when the video output is really emitting PQ/HLG, i.e. HDR passthrough
  -- is live. The chrome gets a heavier outline and a denser scrim, because an
  -- SDR overlay in a PQ swapchain otherwise reads as grey. See [set_output_space].
  hdr = false,
  -- True when the host's independent SDR window owns the bottom band. Set by
  -- the `chrome` IPC command; the property path is kept only as a fallback for
  -- older hosts.
  chrome_window = false,
  has_video = true,
  ui_scale = 1,
}

local seq = 0
local hide_timer = nil

-- Forward declarations. Lua locals are not hoisted: the menu section above the
-- render section calls back into it, so these names must exist first.
-- Forward declarations. `build_menu` reaches back into the menu machinery it is
-- part of (opening a sub-menu from a row), which only works if the names exist
-- before it is defined; a later `local function` would shadow them instead.
local mark_dirty, render, show_ui, schedule_hide, send_back, close_menu, open_menu
local send_fullscreen

local function now()
  return mp.get_time()
end

local function toast(message, seconds)
  state.toast = { text = message, expires = now() + (seconds or 2.2) }
  mark_dirty()
end

-- ==== HELPERS ==============================================================

local function esc_key_name(raw)
  raw = tostring(raw or '')
  local mods = {}
  local base = raw
  while true do
    local head, rest = base:match('^([%w]+)%+(.+)$')
    if not head then
      break
    end
    table.insert(mods, head)
    base = rest
  end
  return base, mods
end

local function has_mod(mods, name)
  for _, m in ipairs(mods) do
    if m == name then
      return true
    end
  end
  return false
end

local function path_name()
  local path = mp.get_property('path') or ''
  local _, name = utils.split_path(path)
  return name or path
end

--- Normalises a path into a storage key.
---
--- Windows paths are case-insensitive, so `C:\Films\A.mkv` and `c:\films\a.mkv`
--- are one file and must share one record. URLs are *not* case-insensitive — an
--- Emby item id is a case-sensitive path segment — so a scheme is left alone.
local function normalize_key(raw)
  local text = tostring(raw or ''):gsub('\\', '/')
  if text:find('://', 1, true) then
    return text
  end
  local collapsed = text:gsub('/+', '/')
  return collapsed:lower()
end

--- The identity of the file mpv currently has open.
---
--- The whole path, never the basename: two copies of `S01E01.mkv` in different
--- folders are different episodes.
local function path_key()
  local path = mp.get_property('path') or ''
  if path ~= '' then
    return normalize_key(path)
  end
  -- Streams resolved through the host may have no useful path; the app hands us
  -- a stable item id for exactly this case.
  return normalize_key(mp.get_property('user-data/player/media-id') or '')
end

-- ==== FORMAT / BADGES ======================================================

--- Chinese labels for the reference build's corner badges.
local function hwdec_label(v)
  if not v or v == '' or v == 'no' then
    return '软解'
  end
  local map = {
    ['d3d11va'] = 'D3D11',
    ['d3d11va-copy'] = 'D3D11 回拷',
    ['dxva2'] = 'DXVA2',
    ['nvdec'] = 'NVDEC',
    ['nvdec-copy'] = 'NVDEC 回拷',
    ['vulkan'] = 'Vulkan',
    ['auto'] = '硬解',
    ['auto-safe'] = '硬解',
  }
  return map[v] or v:upper()
end

--- One pill in the meta row.
---
--- `tier` is the whole point, and there are three of them so the row has a
--- hierarchy instead of reading as six identical grey blocks:
---
---   'fact'  — resolution, codec, frame rate, decoder. Not a claim that needs
---             confirming, so it gets a faint plate and no ring.
---   'lit'   — the pipeline *confirmed* this format. Tinted plate + bright ring
---             + full-strength label.
---   'dim'   — the file contains the format but the output chain is not
---             carrying it: an HDR10 film being tone-mapped to SDR, a DTS-HD MA
---             track decoded in software instead of bitstreamed. Outline only,
---             so "present" and "delivered" stay visibly different.
---
--- `video-out-params` / `audio-out-params` decide 'lit', never the source
--- container — the whole point is that a tone-mapped HDR film must not pretend.
local function badge(label, color, tier)
  if tier == true then
    tier = 'lit'
  elseif tier == false then
    tier = 'dim'
  elseif tier == nil then
    tier = 'fact'
  end
  return { text = label, color = color, tier = tier }
end

local function audio_badge_label()
  local name = (mp.get_property('audio-codec-name') or ''):lower()
  local desc = (mp.get_property('audio-codec') or ''):lower()
  local ch = mp.get_property_number('audio-params/channel-count') or 0
  local label
  if name:find('truehd') or name:find('mlp') then
    label = desc:find('atmos') and 'ATMOS' or 'TRUEHD'
  elseif name:find('dts') then
    if desc:find('dts:x') or desc:find('dts%-x') then
      label = 'DTS:X'
    elseif desc:find('ma') then
      label = 'DTS-HD MA'
    elseif desc:find('hra') then
      label = 'DTS-HD'
    else
      label = 'DTS'
    end
  elseif name:find('eac3') then
    label = desc:find('atmos') and 'DD+ ATMOS' or 'DD+'
  elseif name:find('ac3') then
    label = 'DD'
  elseif name ~= '' then
    label = name:upper()
  else
    return ''
  end
  if ch >= 7.5 then
    return label .. ' 7.1'
  elseif ch >= 5.5 then
    return label .. ' 5.1'
  elseif ch == 2 then
    return label .. ' 2.0'
  end
  return label
end

--- "Is the compressed bitstream really leaving the machine?"
---
--- `audio-out-params/format` is the only honest source: asking WASAPI for
--- passthrough and getting `float` back means it refused and mpv decoded.
local function audio_is_passthrough()
  local f = (mp.get_property('audio-out-params/format') or ''):lower()
  if f == '' then
    return false
  end
  if f:find('float') or f:find('^s%d%d') or f:find('^u%d%d') then
    return false
  end
  return true
end

local function badge_items()
  local out = {}

  local w = mp.get_property_number('video-params/w') or 0
  local h = mp.get_property_number('video-params/h') or 0
  if w >= 7600 or h >= 4300 then
    out[#out + 1] = badge('8K', WHITE, 'fact')
  elseif w >= 3800 or h >= 2100 then
    out[#out + 1] = badge('4K', WHITE, 'fact')
  elseif w >= 2500 or h >= 1400 then
    out[#out + 1] = badge('1440p', WHITE, 'fact')
  elseif w >= 1900 or h >= 1060 then
    out[#out + 1] = badge('1080p', WHITE, 'fact')
  elseif w >= 1260 or h >= 700 then
    out[#out + 1] = badge('720p', WHITE, 'fact')
  elseif w > 0 then
    out[#out + 1] = badge(w .. '×' .. h, WHITE, 'fact')
  end

  local codec = (mp.get_property('video-format') or ''):upper()
  local depth = mp.get_property_number('video-params/plane-depth') or 0
  if codec ~= '' then
    out[#out + 1] = badge(codec .. (depth >= 10 and ' 10BIT' or ''), GREY, 'fact')
  end

  local prim = (mp.get_property('video-params/primaries') or ''):lower()
  local gamma = (mp.get_property('video-params/gamma') or ''):lower()
  local oprim = (mp.get_property('video-out-params/primaries') or ''):lower()
  local ogamma = (mp.get_property('video-out-params/gamma') or ''):lower()
  local out_hdr = ((oprim:find('bt%.2020') or oprim:find('2020')) ~= nil)
    and (ogamma == 'pq' or ogamma == 'hlg' or ogamma:find('st2084') ~= nil)
  if prim:find('dolbyvision') then
    out[#out + 1] = badge('DOLBY VISION', DV_PURPLE, out_hdr and 'lit' or 'dim')
  elseif gamma == 'hlg' then
    out[#out + 1] = badge('HLG', HLG_CYAN, out_hdr and 'lit' or 'dim')
  elseif gamma == 'pq' or gamma:find('st2084') then
    local peak = mp.get_property_number('video-params/sig-peak') or 0
    out[#out + 1] = badge(peak >= 900 and 'HDR10' or 'HDR', HDR_GOLD, out_hdr and 'lit' or 'dim')
  end

  local audio = audio_badge_label()
  if audio ~= '' then
    out[#out + 1] = badge(audio, DTS_AMBER, audio_is_passthrough() and 'lit' or 'dim')
  end

  local fps = mp.get_property_number('container-fps') or 0
  if fps > 0 then
    out[#out + 1] = badge(string.format('%.3gFPS', fps), DIM, 'fact')
  end

  local hw = mp.get_property('hwdec-current')
  local hw_on = hw ~= nil and hw ~= '' and hw ~= 'no'
  out[#out + 1] = badge(hwdec_label(hw), hw_on and GREY or DIM, hw_on and 'fact' or 'dim')

  return out
end

-- ==== SEGMENTS =============================================================
--
-- Every mark is one EDL edit — `start, end, action` — which is the shape Kodi
-- defined in `xbmc/video/Edl.cpp` and the shape of a `<video>.edl` sidecar, so
-- the same record can be exported for other players instead of being a private
-- blob. Actions: `cut` removes the span from playback, `mute` only silences it,
-- `commbreak` is an ad break (muted, but labelled differently).
--
-- Records are keyed by the **full path**. Version 1 keyed them by bare file
-- name, which meant `C:\A\S01E01.mkv` and `D:\B\S01E01.mkv` shared one mark —
-- mark the opening of one episode and every copy of it on every drive skipped
-- the wrong two minutes. `adopt_legacy` migrates those records once.

local SEG_CACHE = nil
local SEG_PATH = nil

--- Action used when a record predates the action column.
local DEFAULT_ACTION = 'cut'

local function segments_path()
  if SEG_PATH then
    return SEG_PATH
  end
  local custom = mp.get_property('user-data/player/data-dir')
  local base = os.getenv('APPDATA') or os.getenv('HOME') or '.'
  local dir = (type(custom) == 'string' and custom ~= '')
    and custom
    or utils.join_path(base, 'XnX Player')
  local probe = io.open(utils.join_path(dir, 'segments.json'), 'r')
  if probe then
    probe:close()
  else
    -- The app already owns this folder (state.json); mkdir -p is idempotent.
    os.execute('mkdir "' .. dir .. '" >nul 2>nul')
  end
  SEG_PATH = utils.join_path(dir, 'segments.json')
  return SEG_PATH
end

local function load_segments()
  if SEG_CACHE then
    return SEG_CACHE
  end
  local file = io.open(segments_path(), 'r')
  if not file then
    SEG_CACHE = {}
    return SEG_CACHE
  end
  local body = file:read('*a')
  file:close()
  local ok, parsed = pcall(utils.parse_json, body)
  if ok and type(parsed) == 'table' then
    SEG_CACHE = parsed
  else
    SEG_CACHE = {}
  end
  return SEG_CACHE
end

local function save_segments()
  if not SEG_CACHE then
    return
  end
  local file = io.open(segments_path(), 'w')
  if not file then
    return
  end
  file:write(utils.format_json(SEG_CACHE))
  file:close()
end

-- ==== BOOKMARKS ============================================================
--
-- Points, not spans. The EDL section above answers "which part of this file
-- must not play"; this answers "which moment is worth coming back to". Both
-- live in the same per-file record, because they are the same kind of fact: a
-- claim the viewer made about this file, keyed by its full path.
--
-- The reference build keeps bookmarks in the video database, each with a
-- rendered thumbnail and a saved player state. Neither is reproducible here — a
-- screenshot would stall the picture for a frame, and there is no window to
-- browse them in — so what is left is the part that matters: timestamp, jump,
-- delete, and a tick on the bar so they are not invisible until opened.

--- How close a second press must be to toggle instead of adding a new mark.
---
--- Kodi splits "add" (Ctrl+B) from "delete" (a key inside the bookmark window).
--- With no window, one key has to do both, and this tolerance is what stops a
--- slightly-off second press from stacking two marks half a second apart.
local BOOKMARK_SNAP = 2

--- Marks stored for one entry, in playback order.
local function entry_bookmarks(entry)
  local out = {}
  if type(entry) ~= 'table' or type(entry.bookmarks) ~= 'table' then
    return out
  end
  for _, mark in ipairs(entry.bookmarks) do
    local at = tonumber(type(mark) == 'table' and mark.at or mark)
    if at and at >= 0 then
      out[#out + 1] = { at = at, label = type(mark) == 'table' and mark.label or nil }
    end
  end
  table.sort(out, function(a, b)
    return a.at < b.at
  end)
  return out
end

--- Replaces the stored list and republishes it to the bar.
local function store_bookmarks(list)
  local entry, key, all = segment_entry()
  if not key or key == '' or not all then
    return false
  end
  if not entry then
    entry = {}
    all[key] = entry
  end
  -- An empty list drops the key instead of storing `[]`: a file with no marks
  -- should leave no trace in the file, and the reader already treats a missing
  -- list as empty. If that leaves the whole entry empty, the entry goes too —
  -- otherwise every file the user bookmarked once and cleared would keep an
  -- empty `{}` in segments.json for ever.
  entry.bookmarks = #list > 0 and list or nil
  if next(entry) == nil then
    all[key] = nil
  end
  SEG_CACHE = all
  save_segments()
  state.bookmarks = list
  mark_dirty()
  return true
end

--- Adds a mark here, or removes the one already here.
local function toggle_bookmark()
  local pos = state.position or 0
  if pos <= 0 then
    return
  end
  local list = entry_bookmarks(segment_entry())
  for i, mark in ipairs(list) do
    if math.abs(mark.at - pos) <= BOOKMARK_SNAP then
      table.remove(list, i)
      if store_bookmarks(list) then
        toast('已移除 ' .. fmt_time(mark.at) .. ' 的书签')
      end
      return
    end
  end
  -- Tenth of a second: enough to be reproducible, coarse enough that the file
  -- stays readable when opened by hand.
  list[#list + 1] = { at = math.floor(pos * 10 + 0.5) / 10 }
  if store_bookmarks(list) then
    toast('已添加书签 ' .. fmt_time(pos))
  end
end

local function clear_bookmarks()
  if #entry_bookmarks(segment_entry()) == 0 then
    return false
  end
  return store_bookmarks({})
end

--- Re-reads the stored marks into `state` so the bar can draw them.
local function refresh_bookmarks()
  state.bookmarks = entry_bookmarks(segment_entry())
end

--- Chapter names that the reference build treats as skippable.
local function classify_chapter(name)
  local s = (name or ''):lower()
  if s:find('opening') or s:find('intro') or s:find('片头') or s:find('主题曲') or s:find('^op') then
    return 'intro'
  end
  if s:find('ending') or s:find('outro') or s:find('片尾') or s:find('^ed') or s:find('credits') then
    return 'outro'
  end
  return nil
end

--- Normalises the action column.
---
--- Records written by this app use the words, but a `.edl` imported from
--- elsewhere may use Kodi's numeric codes (`0/1/2`) or a longer spelling, and
--- mistaking a cut for a mute would either leak two minutes of ads or silence
--- the opening titles.
---
--- Note the absence of `2`: in Kodi's EDL numbering that is a scene marker, a
--- point on the timeline with no interval, not a commercial break. It is
--- decoded by name in `parse_edl` so a stray `.edl` cannot invent a skip.
local ACTION_ALIASES = {
  ['0'] = 'cut',
  ['1'] = 'mute',
  ['3'] = 'commbreak',
  commercial = 'commbreak',
  commercial_break = 'commbreak',
  ad = 'commbreak',
  skip = 'cut',
}

local function normalize_action(raw)
  local text = tostring(raw or DEFAULT_ACTION):lower()
  return ACTION_ALIASES[text] or text
end

--- Reads one stored record into a normalised edit list.
---
--- Two shapes are accepted, and both survive a round trip through the file:
---
---   v2  { edits = { { start=, end=, action=, slot= }, … } }
---   v1  { intro = { start=, end= }, outro = { … } }
---
--- A half-marked edit (start but no end) is *kept* — otherwise pressing Alt+N
--- once, closing the player and pressing it again would start over instead of
--- closing the mark.
local function entry_edits(entry)
  local out = {}
  if type(entry) ~= 'table' then
    return out
  end
  local edits = entry.edits
  if type(edits) == 'table' then
    for _, edit in ipairs(edits) do
      if type(edit) == 'table' then
        local finish = tonumber(edit['end'])
        local start = tonumber(edit.start)
        if start and (not finish or finish > start) then
          out[#out + 1] = {
            start = start,
            ['end'] = finish,
            action = normalize_action(edit.action),
            slot = edit.slot,
          }
        end
      end
    end
    return out
  end
  for _, slot in ipairs({ 'intro', 'outro' }) do
    local pair = entry[slot]
    if type(pair) == 'table' then
      local start = tonumber(pair['start'])
      local finish = tonumber(pair['end'])
      if start and (not finish or finish > start) then
        out[#out + 1] = {
          start = start,
          ['end'] = finish,
          action = DEFAULT_ACTION,
          slot = slot,
        }
      end
    end
  end
  return out
end

local function sort_edits(list)
  table.sort(list, function(a, b)
    return a.start < b.start
  end)
  return list
end

--- Effective edits are recomputed whenever a mark, a chapter or the file
--- changes, not on every tick: the playhead observer runs dozens of times a
--- second and the answer only depends on state that rarely moves.
local EDIT_CACHE = nil

local function invalidate_edits()
  EDIT_CACHE = nil
end

local function is_complete(edit)
  return type(edit) == 'table' and tonumber(edit['end']) ~= nil and edit['end'] > edit.start
end

--- The stored record for the current file, migrating a v1 key if it exists.
local function segment_entry()
  local key = path_key()
  if key == '' then
    return nil, nil, nil
  end
  local all = load_segments()
  local entry = all[key]
  if type(entry) == 'table' then
    return entry, key, all
  end
  -- v1 stored marks under the bare file name. Adopt the record once, then every
  -- later read finds it under the full path.
  local name = path_name()
  for _, legacy in ipairs({ name, (name or ''):lower() }) do
    if legacy ~= '' and legacy ~= key and type(all[legacy]) == 'table' then
      local adopted = all[legacy]
      all[legacy] = nil
      all[key] = adopted
      SEG_CACHE = all
      save_segments()
      return adopted, key, all
    end
  end
  return nil, key, all
end

--- Edit list of the current file plus a writer that persists it.
---
--- Returning `(edits, commit)` keeps every mutation on one path: callers push to
--- `edits` and call `commit()`, which normalises the record to the v2 shape so a
--- migrated file never keeps the old layout around.
local function editable_segments()
  local entry, key, all = segment_entry()
  if not key then
    return nil, nil
  end
  local edits = entry_edits(entry)
  local function commit()
    local packed = {}
    for _, edit in ipairs(edits) do
      packed[#packed + 1] = {
        start = edit.start,
        ['end'] = edit['end'],
        action = edit.action or DEFAULT_ACTION,
        slot = edit.slot,
      }
    end
    all[key] = { edits = packed }
    SEG_CACHE = all
    save_segments()
    invalidate_edits()
  end
  return edits, commit
end

--- Edits a chapter list implies: a chapter says where a segment starts and the
--- following chapter says where it ends.
local function chapter_edits()
  local out = {}
  local chapters = state.chapters
  for _, chapter in ipairs(chapters) do
    local slot = classify_chapter(chapter.title)
    if slot and chapter.time then
      local next_time = nil
      for _, other in ipairs(chapters) do
        if other.time and other.time > chapter.time + 1 then
          if not next_time or other.time < next_time then
            next_time = other.time
          end
        end
      end
      if next_time then
        out[#out + 1] = {
          start = chapter.time,
          ['end'] = next_time,
          action = DEFAULT_ACTION,
          slot = slot,
          from_chapter = true,
        }
      end
    end
  end
  return out
end

-- ==== SIDECAR EDITS (`.edl` / comskip `.txt`) ==============================
--
-- Two file formats sitting beside the video, both read the way the reference
-- build reads them:
--
--   `Show.mkv.edl`  `start end action`, one edit per line. Times are
--                   `HH:MM:SS.mmm` — **milliseconds**, not frames — or plain
--                   seconds, or `#12345` for a frame number. Actions are
--                   Kodi's codes: 0 cut, 1 mute, 2 scene marker, 3 ad break.
--                   Fields are whitespace separated; `##` starts a comment.
--
--   `Show.txt`      comskip's own output. Line 1 is
--                   `FILE PROCESSING COMPLETE <frames> FRAMES AT <fps x 100>`
--                   and every line after the ruler is a pair of *frame*
--                   numbers. Because the frame rate travels in the file, the
--                   conversion is exact — no guessing from the container,
--                   which is wrong for anything film-sourced played at 25 fps.
--
-- comskip can also be told to write `.edl`, but it writes `HH:MM:SS.ff` with
-- frames after the dot and keeps the frame rate to itself. That is
-- indistinguishable from milliseconds, and reading it as such shifts every
-- mark by up to a second — so that form is deliberately unsupported. Use
-- comskip's default `.txt` instead.

local SIDECAR_CACHE = nil
local SIDECAR_SOURCE = nil

local function local_video_path()
  local path = mp.get_property('path') or ''
  if path == '' or path:find('://', 1, true) then
    return ''
  end
  return path
end

--- Folder and extension-less name of a path.
local function split_stem(path)
  local folder, name = utils.split_path(path)
  local stem = name:match('^(.*)%.[^.]*$') or name
  return folder or '', stem
end

--- Reads a whole file, or nil. `io.open` goes through the C library, so a path
--- outside the active code page throws instead of failing — hence the pcall:
--- a sidecar that cannot be opened must never take playback with it.
local function read_text(path)
  local ok, file = pcall(io.open, path, 'r')
  if not ok or not file then
    return nil
  end
  local body = file:read('*a')
  file:close()
  return body
end

--- Seeks are relative to the video, so the container's rate is the right
--- fallback for a comskip file that omitted its header rate.
local function container_fps()
  local ok, value = pcall(mp.get_property_number, 'video-params/fps')
  if ok and type(value) == 'number' and value > 0 then
    return value
  end
  return nil
end

--- `HH:MM:SS.mmm`, `MM:SS.mmm`, plain seconds, or `#frames`.
---
--- The fractional part of a time code is the fraction of the second it names,
--- so `12.45` and a padded `.450` agree — one conversion covers both.
local function parse_edl_time(raw, fps)
  local text = tostring(raw or ''):gsub(',', '.')
  if text == '' then
    return nil
  end
  if text:sub(1, 1) == '#' then
    local frames = tonumber(text:sub(2))
    if not frames or not fps or fps <= 0 then
      return nil
    end
    return frames / fps
  end
  local hours, minutes, seconds = text:match('^(%d+):(%d+):(%d+%.?%d*)$')
  if hours then
    return tonumber(hours) * 3600 + tonumber(minutes) * 60 + tonumber(seconds)
  end
  local mins, secs = text:match('^(%d+):(%d+%.?%d*)$')
  if mins then
    return tonumber(mins) * 60 + tonumber(secs)
  end
  return tonumber(text)
end

--- Kodi's action codes. 2 is a scene marker and carries no interval, so it is
--- absent here on purpose — treating it as an ad break would cut a minute out
--- of the middle of the film wherever the file marked a chapter.
local EDL_ACTIONS = { ['0'] = 'cut', ['1'] = 'mute', ['3'] = 'commbreak' }

--- Only the three interval-bearing actions are accepted. Anything else — a
--- scene marker, a misspelling, a column that is not an action at all — is
--- dropped, because the default for an unknown action would be to cut, and
--- cutting on a guess is the one failure mode that destroys the film.
local function known_action(raw)
  local action = EDL_ACTIONS[raw] or normalize_action(raw)
  if action == 'cut' or action == 'mute' or action == 'commbreak' then
    return action
  end
  return nil
end

local function parse_edl(body, fps)
  local out = {}
  for line in body:gmatch('[^\r\n]+') do
    -- A decimal comma inside a time code is not a field separator.
    local cooked = line:gsub('(%d),(%d)', '%1.%2')
    local fields = {}
    for token in cooked:gmatch('[^%s]+') do
      fields[#fields + 1] = token
    end
    local comment = #fields > 0 and fields[1]:sub(1, 2) == '##'
    if #fields >= 3 and not comment then
      local start = parse_edl_time(fields[1], fps)
      local finish = parse_edl_time(fields[2], fps)
      local action = known_action(fields[3])
      if start and finish and finish > start and action then
        out[#out + 1] = {
          start = start,
          ['end'] = finish,
          action = action,
          from_edl = true,
        }
      end
    end
    -- Two fields is `time action`: a scene marker, not an interval. Skipped.
  end
  return out
end

--- comskip's `.txt`. Returns nil when the file is something else entirely —
--- a stray `.txt` beside the video is far more likely to be notes than an
--- ad list, and a wrong guess would be silent.
local function parse_comskip(body, fallback_fps)
  local lines = {}
  for line in body:gmatch('[^\r\n]+') do
    lines[#lines + 1] = line
  end
  if not (lines[1] or ''):find('FILE PROCESSING COMPLETE', 1, true) then
    return nil
  end
  local rate = tonumber((lines[1]:match('FRAMES AT (%d+)')))
  local fps = (rate and rate > 0) and (rate / 100) or fallback_fps
  if not fps or fps <= 0 then
    -- Frame numbers with no frame rate are not times. Guessing would put the
    -- ads somewhere else entirely.
    return {}
  end
  local out = {}
  for index = 3, #lines do
    local first, second = lines[index]:match('^%s*(%d+%.?%d*)%s+(%d+%.?%d*)')
    if not first then
      -- A malformed tail means the rest cannot be trusted, and half a set of
      -- ad breaks is worse than none.
      return {}
    end
    local start = tonumber(first) / fps
    local finish = tonumber(second) / fps
    if finish > start then
      out[#out + 1] = {
        start = start,
        ['end'] = finish,
        action = 'commbreak',
        from_edl = true,
      }
    end
  end
  return out
end

--- Edits from the sidecar files, read once per file and then cached.
---
--- An `.edl` wins over a leftover comskip run: it is the explicit format, and
--- if someone wrote one they meant it. A `.edl` that parses to nothing is
--- still honoured as "this file has no edits" rather than falling through.
local function sidecar_edits()
  if SIDECAR_CACHE then
    return SIDECAR_CACHE
  end
  SIDECAR_CACHE = {}
  local path = local_video_path()
  if path == '' then
    return SIDECAR_CACHE
  end
  local folder, stem = split_stem(path)
  if stem == '' then
    return SIDECAR_CACHE
  end

  local edl = read_text(utils.join_path(folder, stem .. '.edl'))
  if edl then
    local edits = parse_edl(edl, container_fps())
    if #edits > 0 then
      SIDECAR_CACHE = sort_edits(edits)
      SIDECAR_SOURCE = '.edl'
    end
    return SIDECAR_CACHE
  end

  local txt = read_text(utils.join_path(folder, stem .. '.txt'))
  if txt then
    local edits = parse_comskip(txt, container_fps())
    if edits and #edits > 0 then
      SIDECAR_CACHE = sort_edits(edits)
      SIDECAR_SOURCE = 'comskip'
    end
  end
  return SIDECAR_CACHE
end

--- Drops the cache so a freshly dropped sidecar is picked up without
--- reopening the file.
local function forget_sidecar()
  SIDECAR_CACHE = nil
  SIDECAR_SOURCE = nil
  invalidate_edits()
end

--- Menu label: how many intervals came from beside the file, and from which
--- format, so a silent absence is visibly different from an empty answer.
local function sidecar_label()
  local count = #sidecar_edits()
  if count == 0 then
    return '无'
  end
  return count .. ' 段 · ' .. (SIDECAR_SOURCE or 'EDL')
end

--- What the player should honour right now, sorted by start.
---
--- Three sources, strongest first: a manual mark (the viewer looked at the
--- picture and decided), a sidecar file (a detector decided), a chapter title
--- (a guess). A weaker edit that lands inside a stronger one is dropped rather
--- than merged — two overlapping skips would fight over the playhead.
local function effective_edits()
  if EDIT_CACHE then
    return EDIT_CACHE
  end
  local out = {}
  local function add(edit)
    for _, other in ipairs(out) do
      if edit.start < other['end'] and other.start < edit['end'] then
        return
      end
    end
    out[#out + 1] = edit
  end
  for _, edit in ipairs(entry_edits(segment_entry())) do
    if is_complete(edit) then
      add(edit)
    end
  end
  for _, edit in ipairs(sidecar_edits()) do
    add(edit)
  end
  for _, edit in ipairs(chapter_edits()) do
    add(edit)
  end
  EDIT_CACHE = sort_edits(out)
  return EDIT_CACHE
end

-- ==== ACTIONS ==============================================================

local function command(...)
  mp.commandv(...)
end

local function toggle_pause()
  command('cycle', 'pause')
end

local function seek_abs(target)
  command('seek', tostring(target), 'absolute', 'exact')
end

local function seek_rel(delta)
  command('seek', tostring(delta), 'relative', 'exact')
  if state.menu == nil then
    if delta < 0 then
      toast('« ' .. fmt_time(math.abs(delta)))
    else
      toast('» ' .. fmt_time(delta))
    end
  end
end

-- Seek ladder, the shape `SeekHandler.cpp` uses: the first press is a nudge,
-- and pressing again inside a short window climbs a ladder of step sizes
-- instead of repeating the same nudge. With a flat 5 s step, rewinding ten
-- minutes took 120 presses; the ladder does it in seven.
--
-- The two columns are separate ladders: the plain arrow key nudges, Shift is
-- the shoulder-button jump. Sharing one counter between them meant a Shift press
-- after two taps of the arrow key started at the third rung.
local SEEK_NUDGE = { 5, 10, 30, 60, 180, 300, 600, 1800 }
local SEEK_JUMP = { 15, 60, 300, 1800 }
local SEEK_LADDER_RESET = 0.9
--- Two presses closer together than this are the OS repeating the key, not a
--- person pressing it again.
local SEEK_LADDER_REPEAT = 0.12
--- How often a held key is allowed to actually move the picture.
local SEEK_LADDER_FIRE = 0.2

local seek_ladder = { key = '', direction = 0, step = 0, total = 0, from = 0, at = 0, fired = 0 }

local function seek_step(direction, steps, key)
  local stamp = now()
  local gap = stamp - seek_ladder.at
  local same = seek_ladder.key == key and seek_ladder.direction == direction
  local held = same and gap < SEEK_LADDER_REPEAT

  if not same or gap > SEEK_LADDER_RESET then
    seek_ladder.step = 0
    seek_ladder.total = 0
    -- The destination is measured from where the burst started, not from the
    -- last `time-pos`: the observer lags a seek by a frame or two, so adding up
    -- positions would drift over a long hold.
    seek_ladder.from = state.position or 0
  elseif not held then
    seek_ladder.step = math.min(seek_ladder.step + 1, #steps)
  end
  seek_ladder.key = key
  seek_ladder.direction = direction
  seek_ladder.at = stamp

  -- A held key stays on the rung it started on: climbing while the OS repeats
  -- the key reaches the thirty-minute rung within a second or two of holding,
  -- which lands a long way past anywhere the viewer meant to go. Holding keeps
  -- nudging instead, at a rate the eye can follow.
  if held and stamp - seek_ladder.fired < SEEK_LADDER_FIRE then
    return
  end
  seek_ladder.fired = stamp

  local size = steps[seek_ladder.step] or steps[#steps]
  seek_ladder.total = seek_ladder.total + size * direction
  command('seek', tostring(size * direction), 'relative', 'exact')

  -- One label that grows with the burst, rather than a toast per press landing
  -- on top of the one before it.
  local mark = direction < 0 and '«' or '»'
  local text = mark .. ' ' .. fmt_time(math.abs(seek_ladder.total))
  if state.duration > 0 then
    local aim = math.max(0, math.min(state.duration, seek_ladder.from + seek_ladder.total))
    text = text .. ' · ' .. fmt_time(aim)
  end
  if state.menu == nil then
    toast(text, 1.4)
  end
end

local function add_volume(delta)
  -- Read-then-set: commands are queued, so reading back right after would give
  -- the previous value and the toast would lag one step behind.
  local current = mp.get_property_number('volume') or 0
  local next_volume = math.max(0, math.min(130, current + delta))
  command('set', 'volume', string.format('%.1f', next_volume))
  toast('音量 ' .. round(next_volume) .. '%')
end

local function toggle_mute()
  local muted = mp.get_property_bool('mute', false)
  mp.set_property('mute', muted and 'no' or 'yes')
  toast(muted and '已取消静音' or '已静音')
end

local function set_speed(v)
  v = math.max(0.1, math.min(8, v))
  command('set', 'speed', string.format('%.2f', v))
  toast('播放速度 ' .. string.format('%.2f', v) .. '×')
end

local function speed_ratio(r)
  local cur = mp.get_property_number('speed') or 1
  set_speed(cur * r)
end

local function cycle_track(kind, direction)
  local prop = ({ audio = 'aid', sub = 'sid', video = 'vid' })[kind]
  if not prop then
    return
  end
  if direction < 0 then
    command('cycle-values', prop, 'down')
  else
    command('cycle', prop)
  end
end

local function toggle_sub_visibility()
  local on = mp.get_property_bool('sub-visibility', true)
  mp.set_property('sub-visibility', on and 'no' or 'yes')
  toast(on and '字幕已隐藏' or '字幕已显示')
end

local function adjust_sub_delay(delta)
  local current = mp.get_property_number('sub-delay') or 0
  local next_delay = current + delta
  mp.set_property_number('sub-delay', next_delay)
  toast(string.format('字幕延迟 %+.1f s', next_delay))
end

local function adjust_audio_delay(delta)
  local current = mp.get_property_number('audio-delay') or 0
  local next_delay = current + delta
  mp.set_property_number('audio-delay', next_delay)
  toast(string.format('音频延迟 %+.3f s', next_delay))
end

local function screenshot(with_subs)
  local flag = with_subs and 'subtitles' or 'video'
  command('screenshot', flag)
  local dir = mp.get_property('screenshot-directory') or ''
  toast(dir ~= '' and ('截图已保存到 ' .. dir) or '截图已保存')
end

local function frame_step(dir)
  if dir < 0 then
    command('frame-back-step')
  else
    command('frame-step')
  end
end

local function cycle_loop()
  local cur = mp.get_property('loop-file') or 'no'
  if cur ~= 'no' then
    mp.set_property('loop-file', 'no')
    mp.set_property('loop-playlist', 'no')
    toast('循环：关闭')
  else
    local pl = mp.get_property('loop-playlist') or 'no'
    if pl ~= 'no' then
      mp.set_property('loop-playlist', 'no')
      mp.set_property('loop-file', 'inf')
      toast('循环：单集')
    else
      mp.set_property('loop-playlist', 'inf')
      toast('循环：列表')
    end
  end
end

--- Marks a boundary in the current file: start → end → cleared.
---
--- Three presses walk one slot, which is why a half mark is persisted instead of
--- being thrown away. Two slots exist because the two ends of an episode are
--- separate decisions; `intro` keeps the Alt+N it has always had.
local function mark_segment(slot)
  slot = slot or 'intro'
  local label = (slot == 'outro') and '片尾' or '片头'
  local shortcut = (slot == 'outro') and 'Alt+E' or 'Alt+N'
  local edits, commit = editable_segments()
  if not edits then
    toast('当前文件没有可保存的路径，标记未保存', 3)
    return
  end
  local index, existing = nil, nil
  for i, edit in ipairs(edits) do
    if edit.slot == slot then
      index, existing = i, edit
      break
    end
  end
  local pos = state.position
  if not existing then
    edits[#edits + 1] = {
      start = pos,
      ['end'] = nil,
      action = DEFAULT_ACTION,
      slot = slot,
    }
    commit()
    toast(string.format('%s起点 %s，再按 %s 标记终点', label, fmt_time(pos), shortcut))
  elseif not is_complete(existing) then
    if pos <= existing.start + 0.5 then
      toast('终点必须在起点之后')
      return
    end
    existing['end'] = pos
    commit()
    toast(string.format('%s %s – %s 已保存', label, fmt_time(existing.start), fmt_time(pos)))
  else
    table.remove(edits, index)
    commit()
    toast(label .. '标记已清除')
  end
end

--- How a slot reads in the menu: empty, half-marked, or a saved span.
local function mark_label(slot)
  local entry = segment_entry()
  for _, edit in ipairs(entry_edits(entry)) do
    if edit.slot == slot then
      if is_complete(edit) then
        return fmt_time(edit.start) .. ' – ' .. fmt_time(edit['end'])
      end
      return '起点 ' .. fmt_time(edit.start)
    end
  end
  return '无'
end

-- Playback-time consequences of the edits. `cut_seen` exists so the toast for a
-- skip is emitted once per region instead of on every rewind through it.
local cut_seen = {}
local muted_by_edits = false
local mute_was_on = false

local function release_edit_mute()
  if not muted_by_edits then
    return
  end
  muted_by_edits = false
  -- Never un-mute a file the viewer had already silenced themselves.
  if not mute_was_on then
    mp.set_property('mute', 'no')
  end
  mute_was_on = false
end

--- Applies cuts and mutes to the playhead.
---
--- Runs from the time-pos observer, so it covers both playback drifting into a
--- region and a seek landing inside one — those are the same event as far as a
--- cut is concerned. Gated on the preference the UI exposes: turning skipping
--- off must leave the file untouched, mutes included.
local function apply_edits()
  if mp.get_property('user-data/player/skip-intro') ~= 'yes' then
    release_edit_mute()
    return
  end
  local pos = state.position
  local active = nil
  for _, edit in ipairs(effective_edits()) do
    if edit.start > pos then
      break
    end
    if pos < edit['end'] then
      active = edit
    end
  end
  if not active then
    release_edit_mute()
    return
  end
  if active.action == 'mute' then
    if not muted_by_edits then
      mute_was_on = mp.get_property('mute') == 'yes'
      muted_by_edits = true
      mp.set_property('mute', 'yes')
      toast('静音片段 · ' .. fmt_time(active['end'] - active.start), 3)
    end
    return
  end
  -- Everything else is cut: an explicit cut, a commercial break, a chapter of
  -- the opening. Only `mute` is treated as sound-off, so an ad break read from
  -- a sidecar plays silently only if the file said so.
  release_edit_mute()
  -- Leave the last fraction of a second alone: a seek that lands one keyframe
  -- short of the cut end would otherwise bounce back and forth forever.
  if pos < active['end'] - 0.3 then
    seek_abs(active['end'])
    if not cut_seen[active.start] then
      cut_seen[active.start] = true
      local label = '剪辑段'
      if active.slot == 'intro' then
        label = '片头'
      elseif active.slot == 'outro' then
        label = '片尾'
      elseif active.action == 'commbreak' then
        label = active.from_edl and '广告段（EDL）' or '广告段'
      end
      toast('已跳过' .. label .. ' · ' .. fmt_time(active['end'] - active.start), 3)
    end
  end
end

--- Forgets per-file runtime state. Called when a new file is loaded, because
--- the same timestamps on the next episode mean something else entirely.
local function reset_edits()
  cut_seen = {}
  release_edit_mute()
  -- The next episode has its own sidecar beside it, or none at all.
  forget_sidecar()
end

-- ==== MENUS ================================================================

local function track_rows(kind)
  local rows = {}
  local list = mp.get_property_native('track-list') or {}
  local current = mp.get_property(kind == 'audio' and 'aid' or 'sid')
  for _, track in ipairs(list) do
    if track.type == kind then
      local label = track.title
      if not label or label == '' then
        local bits = {}
        if track.lang and track.lang ~= '' then
          table.insert(bits, track.lang:upper())
        end
        if track.codec and track.codec ~= '' then
          table.insert(bits, track.codec:upper())
        end
        if track.channels and track.channels > 0 then
          table.insert(bits, tostring(track.channels) .. 'ch')
        end
        label = #bits > 0 and table.concat(bits, ' · ') or ('轨道 ' .. tostring(track.id))
      end
      if track.external then
        label = label .. '（外挂）'
      end
      table.insert(rows, {
        label = label,
        active = track.selected == true or tostring(track.id) == tostring(current),
        kind = 'item',
        act = function()
          mp.set_property_native(kind == 'audio' and 'aid' or 'sid', track.id)
          toast('已切换：' .. label)
        end,
      })
    end
  end
  return rows
end

local function build_menu(id)
  local rows = {}
  if id == 'audio' then
    rows = track_rows('audio')
    table.insert(rows, 1, {
      label = '关闭音轨',
      active = (mp.get_property('aid') or 'no') == 'no',
      kind = 'item',
      act = function()
        mp.set_property('aid', 'no')
        toast('音轨已关闭')
      end,
    })
    local delay = mp.get_property_number('audio-delay') or 0
    table.insert(rows, { kind = 'header', label = '音频调整' })
    table.insert(rows, {
      label = '延迟',
      value = string.format('%+.3f s', delay),
      kind = 'adjust',
      act = function(d)
        adjust_audio_delay(d * 0.05)
      end,
    })
    table.insert(rows, {
      label = '音量',
      value = tostring(round(mp.get_property_number('volume') or 0)) .. '%',
      kind = 'adjust',
      act = function(d)
        add_volume(d * 5)
      end,
    })
    table.insert(rows, {
      label = '静音',
      value = mp.get_property('mute') or 'no',
      kind = 'adjust',
      act = function()
        toggle_mute()
      end,
    })
  elseif id == 'subtitle' then
    rows = track_rows('sub')
    table.insert(rows, 1, {
      label = '关闭字幕',
      active = not mp.get_property_bool('sub-visibility', true),
      kind = 'item',
      act = function()
        mp.set_property('sub-visibility', 'no')
        toast('字幕已关闭')
      end,
    })
    table.insert(rows, 2, {
      label = '加载外部字幕…',
      kind = 'item',
      act = function()
        seq = seq + 1
        mp.commandv('script-message', 'player-event',
          utils.format_json({ type = 'subtitle', seq = seq }))
      end,
    })
    local delay = mp.get_property_number('sub-delay') or 0
    local size = mp.get_property_number('sub-font-size') or 42
    local pos = mp.get_property_number('sub-pos') or 100
    table.insert(rows, { kind = 'header', label = '字幕调整' })
    table.insert(rows, {
      label = '延迟',
      value = string.format('%+.1f s', delay),
      kind = 'adjust',
      act = function(d)
        adjust_sub_delay(d * 0.1)
      end,
    })
    table.insert(rows, {
      label = '字号',
      value = tostring(round(size)),
      kind = 'adjust',
      act = function(d)
        mp.set_property_number('sub-font-size', math.max(16, math.min(96, size + d * 2)))
      end,
    })
    table.insert(rows, {
      label = '垂直位置',
      value = tostring(round(pos)) .. '%',
      kind = 'adjust',
      act = function(d)
        mp.set_property_number('sub-pos', math.max(0, math.min(150, pos + d * 5)))
      end,
    })
  elseif id == 'chapters' then
    local chapters = state.chapters
    if #chapters == 0 then
      table.insert(rows, { label = '这个文件没有章节', kind = 'header' })
    end
    for i, chapter in ipairs(chapters) do
      table.insert(rows, {
        label = chapter.title or ('章节 ' .. tostring(i)),
        value = fmt_time(chapter.time or 0),
        active = (state.chapter == i - 1),
        kind = 'item',
        act = function()
          seek_abs(chapter.time or 0)
        end,
      })
    end
  elseif id == 'bookmarks' then
    local marks = state.bookmarks or {}
    for _, mark in ipairs(marks) do
      table.insert(rows, {
        label = mark.label or fmt_time(mark.at),
        value = (state.position and math.abs(state.position - mark.at) < 1) and '当前' or nil,
        kind = 'item',
        act = function()
          -- Closing on the way out is the difference between "jump there" and
          -- "jump there and cover the picture with a menu".
          seek_abs(mark.at)
          close_menu()
        end,
      })
    end
    if #marks == 0 then
      table.insert(rows, { label = '这个文件还没有书签', kind = 'header' })
    end
    table.insert(rows, {
      label = '在当前位置添加',
      value = fmt_time(state.position or 0),
      kind = 'item',
      act = function()
        toggle_bookmark()
      end,
    })
    if #marks > 0 then
      table.insert(rows, {
        label = '清空全部书签',
        kind = 'item',
        act = function()
          if clear_bookmarks() then
            toast('书签已清空')
          end
        end,
      })
    end
  elseif id == 'speed' then
    for _, preset in ipairs({ 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0 }) do
      table.insert(rows, {
        label = string.format('%.2f×', preset),
        value = preset == 1.0 and '正常' or nil,
        active = math.abs((mp.get_property_number('speed') or 1) - preset) < 0.01,
        kind = 'item',
        act = function()
          set_speed(preset)
        end,
      })
    end
  elseif id == 'playlist' then
    local list = mp.get_property_native('playlist') or {}
    local current = mp.get_property_number('playlist-pos') or -1
    if #list <= 1 then
      table.insert(rows, { label = '播放列表只有当前文件', kind = 'header' })
    end
    for i, entry in ipairs(list) do
      local _, short_name = utils.split_path(entry.filename or '')
      local label = entry.title
      if not label or label == '' then
        label = short_name
      end
      if not label or label == '' then
        label = '#' .. tostring(i)
      end
      table.insert(rows, {
        label = clip(label, 44),
        value = i - 1 == current and '播放中' or nil,
        active = i - 1 == current,
        kind = 'item',
        act = function()
          command('playlist-play-index', tostring(i - 1))
        end,
      })
    end
  elseif id == 'video' then
    local function prop_row(label, prop, step, min, max, fmt, unit)
      local cur = mp.get_property_number(prop) or 0
      table.insert(rows, {
        label = label,
        value = string.format(fmt, cur) .. (unit or ''),
        kind = 'adjust',
        act = function(d)
          local v = math.max(min, math.min(max, cur + d * step))
          mp.set_property_number(prop, v)
        end,
      })
    end
    prop_row('亮度', 'brightness', 1, -100, 100, '%.0f')
    prop_row('对比度', 'contrast', 1, -100, 100, '%.0f')
    prop_row('饱和度', 'saturation', 1, -100, 100, '%.0f')
    -- mpv's video equalizer options (brightness/contrast/saturation/gamma) are
    -- all offsets centred on 0 with range -100..100 — gamma is not a 1.0
    -- multiplier, unlike mplayer.
    prop_row('伽马', 'gamma', 1, -100, 100, '%.0f')
    prop_row('缩放', 'video-zoom', 0.02, -1, 1, '%.2f')
    table.insert(rows, {
      label = '镜像',
      value = mp.get_property('video-flip') or 'no',
      kind = 'adjust',
      act = function()
        command('cycle-values', 'video-flip', 'no', 'h')
      end,
    })
    table.insert(rows, {
      label = '旋转',
      value = tostring(round(mp.get_property_number('video-rotate') or 0)) .. '°',
      kind = 'adjust',
      act = function(d)
        local cur = round(mp.get_property_number('video-rotate') or 0)
        mp.set_property_number('video-rotate', (cur + d * 90) % 360)
      end,
    })
    table.insert(rows, { kind = 'header', label = '重置' })
    table.insert(rows, {
      label = '恢复默认画面',
      kind = 'item',
      act = function()
        for _, prop in ipairs({ 'brightness', 'contrast', 'saturation', 'gamma', 'video-zoom' }) do
          mp.set_property_number(prop, 0)
        end
        mp.set_property_number('video-rotate', 0)
        mp.set_property('video-flip', 'no')
        toast('画面已恢复默认')
      end,
    })
  elseif id == 'more' then
    local loop_file = mp.get_property('loop-file') or 'no'
    local loop_pl = mp.get_property('loop-playlist') or 'no'
    local loop_label = '关闭'
    if loop_file ~= 'no' then
      loop_label = '单集'
    elseif loop_pl ~= 'no' then
      loop_label = '列表'
    end
    table.insert(rows, {
      label = '全屏',
      value = 'F11',
      kind = 'item',
      act = function()
        send_fullscreen()
      end,
    })
    table.insert(rows, {
      label = '循环模式',
      value = loop_label,
      kind = 'adjust',
      act = function()
        cycle_loop()
      end,
    })
    table.insert(rows, {
      label = '去色带',
      value = mp.get_property('deband') or 'no',
      kind = 'adjust',
      act = function()
        command('cycle-values', 'deband', 'yes', 'no')
      end,
    })
    table.insert(rows, {
      label = '插帧平滑',
      value = mp.get_property('interpolation') or 'no',
      kind = 'adjust',
      act = function()
        command('cycle-values', 'interpolation', 'yes', 'no')
        local on = mp.get_property('interpolation') == 'yes'
        mp.set_property('video-sync', on and 'display-resample' or 'audio')
        toast(on and '插帧已开启' or '插帧已关闭')
      end,
    })
    table.insert(rows, {
      label = 'HDR 直通',
      value = mp.get_property('target-colorspace-hint') or 'no',
      kind = 'adjust',
      act = function()
        command('cycle-values', 'target-colorspace-hint', 'auto', 'no')
        toast(mp.get_property('target-colorspace-hint') == 'no' and 'HDR 直通已关闭' or 'HDR 直通已开启')
      end,
    })
    table.insert(rows, { kind = 'header', label = '操作' })
    local ab_a = mp.get_property_number('ab-loop-a')
    local ab_b = mp.get_property_number('ab-loop-b')
    local ab_label = '关闭'
    if ab_a then
      ab_label = ab_b and (fmt_time(ab_a) .. ' → ' .. fmt_time(ab_b)) or ('A ' .. fmt_time(ab_a))
    end
    table.insert(rows, {
      label = 'A-B 循环',
      value = ab_label,
      kind = 'adjust',
      act = function()
        local a = mp.get_property_number('ab-loop-a')
        local b = mp.get_property_number('ab-loop-b')
        if not a then
          mp.set_property_number('ab-loop-a', state.position)
          toast('A 点 ' .. fmt_time(state.position))
        elseif not b then
          if state.position <= a then
            toast('B 点必须在 A 点之后')
            return
          end
          mp.set_property_number('ab-loop-b', state.position)
          toast('A-B 循环已开启')
        else
          mp.set_property('ab-loop-a', 'no')
          mp.set_property('ab-loop-b', 'no')
          toast('A-B 循环已关闭')
        end
      end,
    })
    table.insert(rows, {
      label = '画面比例',
      value = mp.get_property('video-aspect-override') or '默认',
      kind = 'adjust',
      act = function()
        command('cycle-values', 'video-aspect-override', 'no', '16:9', '4:3', '2.35:1')
      end,
    })
    table.insert(rows, {
      label = '截图',
      value = 'S',
      kind = 'item',
      act = function()
        screenshot(false)
      end,
    })
    table.insert(rows, {
      label = '片头标记（Alt+N）',
      value = mark_label('intro'),
      kind = 'item',
      act = function()
        mark_segment('intro')
      end,
    })
    table.insert(rows, {
      label = '片尾标记（Alt+E）',
      value = mark_label('outro'),
      kind = 'item',
      act = function()
        mark_segment('outro')
      end,
    })
    table.insert(rows, {
      label = '旁挂 EDL',
      value = sidecar_label(),
      kind = 'item',
      act = function()
        -- Re-read: the point of the row is picking up a file dropped while the
        -- film was already open.
        forget_sidecar()
        local count = #sidecar_edits()
        mark_dirty()
        if count > 0 then
          toast('已载入 ' .. count .. ' 段 · ' .. (SIDECAR_SOURCE or 'EDL'), 3)
        else
          toast('同目录没有 .edl，也没有 comskip 的 .txt', 3)
        end
      end,
    })
    table.insert(rows, {
      label = '书签（Ctrl+B）',
      value = #(state.bookmarks or {}) > 0 and (tostring(#state.bookmarks) .. ' 个') or '无',
      kind = 'item',
      act = function()
        open_menu('bookmarks')
      end,
    })
    table.insert(rows, {
      label = '退出播放',
      value = 'Esc',
      kind = 'item',
      act = function()
        send_back()
      end,
    })
  elseif id == 'stats' then
    -- Stats has its own panel, no rows.
  end
  if #rows == 0 then
    table.insert(rows, { label = '没有可用的项目', kind = 'header' })
  end
  return rows
end

local MENU_TITLES = {
  audio = '音轨',
  subtitle = '字幕',
  chapters = '章节',
  bookmarks = '书签',
  speed = '播放速度',
  playlist = '播放列表',
  video = '画面',
  more = '更多',
}

local function first_selectable(rows, from, step)
  local i = from
  local guard = 0
  while guard < #rows + 2 do
    if i < 1 then
      i = #rows
    elseif i > #rows then
      i = 1
    end
    if rows[i] and rows[i].kind ~= 'header' then
      return i
    end
    i = i + step
    guard = guard + 1
  end
  return 1
end

function open_menu(id)
  if id == 'stats' then
    state.stats = not state.stats
    state.menu = nil
    if state.stats then
      show_ui()
    end
    mark_dirty()
    return
  end
  -- Clicking the button of the menu that is already open closes it; otherwise
  -- the toolbar reads as unresponsive.
  if state.menu and state.menu.id == id then
    close_menu()
    return
  end
  local rows = build_menu(id)
  state.menu = {
    id = id,
    title = MENU_TITLES[id] or id,
    rows = rows,
    index = first_selectable(rows, 1, 1),
  }
  show_ui()
  mark_dirty()
end

function close_menu()
  if state.menu == nil then
    return false
  end
  state.menu = nil
  mark_dirty()
  schedule_hide()
  return true
end

local function menu_move(delta)
  local menu = state.menu
  if not menu then
    return
  end
  menu.index = first_selectable(menu.rows, menu.index + delta, delta < 0 and -1 or 1)
  mark_dirty()
end

local function current_row()
  local menu = state.menu
  if not menu then
    return nil
  end
  return menu.rows[menu.index]
end

local function activate_row()
  local row = current_row()
  if not row then
    return
  end
  if row.kind == 'adjust' then
    if row.act then
      row.act(1)
    end
  elseif row.kind == 'item' then
    if row.act then
      row.act()
    end
    -- Rebuild so "active" ticks and values refresh; keep the same index.
    local menu = state.menu
    if menu then
      local keep = menu.index
      menu.rows = build_menu(menu.id)
      menu.index = math.min(keep, #menu.rows)
    end
  end
  mark_dirty()
end

local function adjust_row(direction)
  local row = current_row()
  if row and row.kind == 'adjust' and row.act then
    row.act(direction)
    local menu = state.menu
    if menu then
      local keep = menu.index
      menu.rows = build_menu(menu.id)
      menu.index = math.min(keep, #menu.rows)
    end
    mark_dirty()
  end
end

-- ==== RENDER ===============================================================

local osd = mp.create_osd_overlay('ass-events')
osd.res_x = W
osd.res_y = H
osd.z = 1000

local hits = {}
local dirty = true

-- ==== MENU HAND-OFF ========================================================
-- When the Dart layer owns the chrome it also draws the menu. Lua stays the
-- model: `row.act` is a closure and cannot cross the IPC boundary, so the whole
-- interaction (move/choose/adjust) is forwarded back here and this side keeps
-- deciding what a row means.
local menu_fingerprint = ''

local function push_menu()
  -- Audio-only keeps the full Lua stage (`dart_chrome` is false there), so the
  -- menu must not be handed over as well or two panels would stack.
  if state.audio_mode then
    if menu_fingerprint ~= '' then
      menu_fingerprint = ''
      mp.commandv('script-message', 'player-event',
        utils.format_json({ type = 'menu', open = false }))
    end
    return
  end
  if not state.chrome_window then
    return
  end
  local menu = state.menu
  if not menu then
    if menu_fingerprint ~= '' then
      menu_fingerprint = ''
      mp.commandv('script-message', 'player-event',
        utils.format_json({ type = 'menu', open = false }))
    end
    return
  end
  local rows = {}
  local pieces = { menu.id or '', tostring(menu.index) }
  for i, row in ipairs(menu.rows) do
    local kind = row.kind or 'item'
    local label = row.label or ''
    local value = row.value and tostring(row.value) or ''
    local active = row.active and true or false
    rows[i] = { kind = kind, label = label, value = value, active = active }
    pieces[#pieces + 1] = kind .. '\x1f' .. label .. '\x1f' .. value .. (active and '\x01' or '')
  end
  local fp = table.concat(pieces, '\x1e')
  if fp == menu_fingerprint then
    return
  end
  menu_fingerprint = fp
  mp.commandv('script-message', 'player-event', utils.format_json({
    type = 'menu',
    open = true,
    title = menu.title or '',
    index = menu.index,
    rows = rows,
  }))
end

function mark_dirty()
  dirty = true
  push_menu()
end

local function add_hit(entry)
  table.insert(hits, entry)
end

local function hit_at(x, y)
  for i = #hits, 1, -1 do
    local h = hits[i]
    if x >= h.x and x <= h.x + h.w and y >= h.y and y <= h.y + h.h then
      return h
    end
  end
  return nil
end

local function button_width(label, size)
  return measure(label, size) + 34
end

local function draw_bar_button(parts, label, x, y, w, h, active, hovered, onClick)
  local bg_alpha = 0x00
  local fg = WHITE
  local fg_alpha = 0x00
  if active then
    bg_alpha = 0xF2
    fg = BLACK
  elseif hovered then
    bg_alpha = 0x2A
  end
  parts[#parts + 1] = rect(x, y, w, h, 12, WHITE, bg_alpha)
  local size = 22
  local tw = measure(label, size)
  parts[#parts + 1] = text(x + (w - tw) / 2, y + (h - 28) / 2, size, fg, fg_alpha, label, 7, false)
  add_hit({ id = 'button:' .. label, x = x, y = y, w = w, h = h, onClick = onClick })
end

local function draw_progress(parts)
  local duration = state.duration
  local live = not duration or duration <= 0
  local ratio = live and 0 or math.max(0, math.min(1, state.position / duration))

  local x, y, w = SAFE, BAR_Y, W - SAFE * 2
  local hovered = state.hover == 'bar'
  local thickness = hovered and 6 or BAR_H
  local top = y - (thickness - BAR_H) / 2

  parts[#parts + 1] = rect(x, top, w, thickness, thickness / 2, WHITE, 0x30)

  if not live then
    local buffer_ratio = math.max(0, math.min(1, (state.buffer or 0) / duration))
    if buffer_ratio > ratio then
      parts[#parts + 1] = rect(x, top, w * buffer_ratio, thickness, thickness / 2, WHITE, 0x1E)
    end
    if ratio > 0.0005 then
      parts[#parts + 1] = rect(x, top, w * ratio, thickness, thickness / 2, WHITE, 0xFF)
      local knob = hovered and 16 or 12
      parts[#parts + 1] = rect(
        x + w * ratio - knob / 2,
        y + BAR_H / 2 - knob / 2,
        knob, knob, knob / 2, WHITE, 0xFF
      )
    end

    -- Chapter ticks.
    for _, chapter in ipairs(state.chapters) do
      if chapter.time and chapter.time > 0 and chapter.time < duration then
        local cx = x + w * (chapter.time / duration)
        parts[#parts + 1] = rect(cx - 1, top - 5, 2, thickness + 10, 1, WHITE, 0x66)
      end
    end

    -- Bookmarks: short gold blocks above the track, against the chapters'
    -- full-height white hairlines. A tick rather than a span, because a
    -- bookmark is a point — drawing it as wide as an edit would promise a
    -- region the player is about to skip, and it skips nothing.
    for _, mark in ipairs(state.bookmarks or {}) do
      if mark.at > 0 and mark.at < duration then
        local bx = x + w * (mark.at / duration)
        parts[#parts + 1] = rect(bx - 3, top - 9, 6, 3, 1.5, BOOKMARK_TINT, 0xD8)
      end
    end

    -- Edits the player honours, split by what they cost the viewer: red for
    -- "this picture goes away", a faint hairline for "this only goes quiet".
    for _, edit in ipairs(effective_edits()) do
      local s = math.max(0, math.min(duration, edit.start))
      local e = math.max(0, math.min(duration, edit['end']))
      if e > s then
        local sx = x + w * (s / duration)
        local span = math.max(2, x + w * (e / duration) - sx)
        if edit.action == 'mute' then
          parts[#parts + 1] = rect(sx, top + thickness + 7, span, 2, 1, WHITE, 0x44)
        else
          parts[#parts + 1] = rect(sx, top + thickness + 3, span, 4, 2, CUT_TINT, 0xB4)
        end
      end
    end
  else
    parts[#parts + 1] = rect(x, top, w, thickness, thickness / 2, WHITE, 0xFF)
  end

  -- Hover scrub bubble.
  if hovered and state.pointer and not live then
    local px = math.max(x, math.min(x + w, state.pointer.x))
    local target = (px - x) / w * duration
    parts[#parts + 1] = rect(px - 1, top - 8, 2, thickness + 16, 1, WHITE, 0xFF)
    local label = fmt_time(target)
    local bw = measure(label, 20) + 24
    parts[#parts + 1] = rect(px - bw / 2, top - 46, bw, 32, 8, BLACK, 0xE8)
    parts[#parts + 1] = text(px, top - 42, 20, WHITE, 0x00, label, 8, false)
  end

  add_hit({ id = 'bar', x = x - 10, y = y - 16, w = w + 20, h = thickness + 32 })
end

local function draw_toast(parts)
  local t = state.toast
  if not t then
    return
  end
  local remaining = t.expires - now()
  if remaining <= 0 then
    state.toast = nil
    return
  end
  local alpha = 0x00
  if remaining < 0.4 then
    alpha = round(0x00 + (0.4 - remaining) / 0.4 * 0xC0)
  end
  local label = t.text
  local tw = measure(label, 26)
  local bw = math.min(W - SAFE * 2, tw + 72)
  local bx = (W - bw) / 2
  parts[#parts + 1] = rect(bx, 66, bw, 60, 30, BLACK, 0xEC)
  parts[#parts + 1] = text(W / 2, 81, 26, WHITE, alpha, clip(label, 46), 8, false)
end

--- Switches the chrome between SDR and HDR-pass-through weightings.
---
--- Driven by `video-target-params` — what the video output is *actually*
--- emitting — not by the source. Tone-mapping an HDR file onto an SDR desktop
--- still composites in SDR, so it keeps the light outline; a PQ swapchain gets
--- the heavy one.
local function set_output_space(hdr)
  if state.hdr == hdr then
    return
  end
  state.hdr = hdr
  HDR_OUTPUT = hdr
  -- Contrast stays (the outline is what keeps 203-nit type legible over a
  -- bright frame), everything that *adds ink* is reduced: a PQ swapchain
  -- already reads darker, and stacking shadow plus dense scrims on top of it
  -- was reported as "OSD 颜色/晕影/阴影被加深".
  TEXT_BORDER = hdr and 2.4 or 1.2
  TEXT_SHADOW = 0
  TEXT_SHADOW_ALPHA = 0x30
  SCRIM_TOP = hdr and 0x30 or 0x4E
  SCRIM_BOTTOM = hdr and 0x40 or 0x62
  -- libass overlays are sRGB; in a PQ swapchain they are anchored to the
  -- 203-nit SDR reference and the white chrome reads grey. Raising the
  -- overlay peak keeps the OSD's SDR contrast without pretending it is HDR
  -- content. Not every build exposes the option, hence the pcall.
  pcall(function()
    mp.set_property('sub-hdr-peak', hdr and '300' or 'auto')
  end)
  mark_dirty()
end

local function draw_scrim(parts)
  -- The reference build (Yaozhi/uosc) draws no scrim at all: the bar floats on
  -- the picture and a hairline text outline does the legibility work. Eight
  -- stacked rectangles with rising opacity were the "格行" bug — every step
  -- boundary is a hard edge, and over metal/snow/sky those edges read as
  -- stripes. Two heavily feathered plates keep a whisper of contrast without
  -- any edge to see, and `text()` now carries a black outline as the real
  -- guarantee.
  parts[#parts + 1] = rect(0, 700, W, H - 700, 0, BLACK, SCRIM_TOP, 42)
  parts[#parts + 1] = rect(0, 840, W, H - 840, 0, BLACK, SCRIM_BOTTOM, 24)
end

-- `video-target-params` is the VO's own description of the swapchain, so this
-- fires once when passthrough engages (or when the display leaves HDR) and
-- never for a file that is merely tone-mapped into SDR.
mp.observe_property('video-target-params', 'native', function(_, value)
  if type(value) ~= 'table' then
    return
  end
  local gamma = value.gamma
  local peak = tonumber(value['max-luma']) or 0
  set_output_space(gamma == 'pq' or gamma == 'hlg' or peak > 203)
end)

local function draw_audio_stage(parts)
  parts[#parts + 1] = rect(0, 0, W, H, 0, BLACK, 0xFF)
  local title = clip(state.title ~= '' and state.title or state.fallback_title, 34)
  parts[#parts + 1] = text(W / 2, H / 2 - 150, 20, DIM, 0x00, '音频播放', 8, false)
  parts[#parts + 1] = text(W / 2, H / 2 - 110, 64, WHITE, 0x00, title, 8, true)
  local audio = mp.get_property('audio-codec-name') or ''
  local channels = mp.get_property_number('audio-params/channel-count') or 0
  local rate = mp.get_property_number('audio-params/samplerate') or 0
  local bits = {}
  if audio ~= '' then
    table.insert(bits, audio:upper())
  end
  if channels > 0 then
    table.insert(bits, tostring(round(channels)) .. ' 声道')
  end
  if rate > 0 then
    table.insert(bits, string.format('%.1f kHz', rate / 1000))
  end
  parts[#parts + 1] = text(W / 2, H / 2 - 20, 22, GREY, 0x00, table.concat(bits, '  ·  '), 8, false)
end

local function draw_stats(parts)
  local function p(name)
    local v = mp.get_property(name)
    if v == nil or v == '' then
      return '—'
    end
    return v
  end
  local function n(name, fmt)
    local v = mp.get_property_number(name)
    if v == nil then
      return '—'
    end
    return string.format(fmt, v)
  end

  local rows = {
    { '文件', clip(path_name(), 46) },
    { '容器', p('file-format') },
    { '大小', fmt_bytes(mp.get_property_number('file-size')) },
    { '时长', fmt_time(state.duration) },
    { '分辨率', n('video-params/w', '%.0f') .. ' × ' .. n('video-params/h', '%.0f') },
    { '视频编码', p('video-codec') },
    { '像素格式', p('video-params/pixelformat') },
    { '位深', n('video-params/plane-depth', '%.0f') .. ' bit' },
    { '色彩空间', p('video-params/primaries') .. ' / ' .. p('video-params/gamma') },
    { '解码', hwdec_label(mp.get_property('hwdec-current')) },
    { '帧率', n('container-fps', '%.3f') .. ' fps' },
    { '实测帧率', n('estimated-vf-fps', '%.2f') .. ' fps' },
    { '显示刷新率', n('display-fps', '%.2f') .. ' Hz' },
    { '丢帧', n('vo-drop-frame-count', '%.0f') .. ' / ' .. n('decoder-frame-drop-count', '%.0f') },
    { '音频编码', p('audio-codec-name') },
    { '声道', n('audio-params/channel-count', '%.0f') },
    { '采样率', n('audio-params/samplerate', '%.0f') .. ' Hz' },
    { '缓存', n('demuxer-cache-duration', '%.1f') .. ' s' },
    { '码率', fmt_rate((mp.get_property_number('file-size') or 0) * 8 / math.max(1, state.duration)) },
    { '播放位置', fmt_time(state.position) },
  }

  -- Two columns so the panel never grows taller than the safe area.
  local per_col = math.ceil(#rows / 2)
  local col_w = 520
  local pw = col_w * 2 + 56
  local ph = 34 + per_col * 40 + 24
  local px, py = SAFE, MENU_BOTTOM - ph
  parts[#parts + 1] = rect(px, py, pw, ph, 26, BLACK, 0xF2)
  -- "The controls do not respond" has two very different causes: mpv never saw a
  -- pointer event, or it saw one and the hitboxes were wrong. This line tells
  -- them apart without a debugger attached.
  local mouse_note = state.mouse_seen and '  ·  鼠标已连接' or '  ·  鼠标未收到事件'
  if state.external_pointer then
    mouse_note = mouse_note .. string.format('（宿主转发 %d 次）', state.mouse_events)
  end
  parts[#parts + 1] = text(px + 28, py + 20, 20, DIM, 0x00, '统计信息 · I 关闭' .. mouse_note, 7, true)
  for i, row in ipairs(rows) do
    local col = i <= per_col and 0 or 1
    local line = col == 0 and i or (i - per_col)
    local cx = px + 28 + col * col_w
    local cy = py + 58 + (line - 1) * 40
    parts[#parts + 1] = text(cx, cy, 20, DIM, 0x00, row[1], 7, false)
    parts[#parts + 1] = text(cx + 152, cy, 20, WHITE, 0x00, row[2], 7, false, MONO)
  end
end

local function draw_help(parts)
  local lines = {
    { '空格 / K', '播放 / 暂停' },
    { '← →', '快退 / 快进 5 秒' },
    { 'Shift + ← →', '快退 / 快进 15 秒' },
    { '↑ ↓', '音量 ±5' },
    { 'M', '静音' },
    { 'J / Shift+J', '下一个 / 上一个字幕' },
    { 'V', '字幕显示开关' },
    { 'Z / X', '字幕延迟 -0.1 / +0.1' },
    { 'A / Shift+A', '下一个 / 上一个音轨' },
    { '[ / ]', '减速 / 加速' },
    { 'Backspace', '恢复 1.0×' },
    { 'C', '下一个章节' },
    { ', / .', '逐帧后退 / 前进' },
    { 'S / Shift+S', '截图 / 含字幕截图' },
    { 'I', '统计信息' },
    { 'L', '循环模式' },
    { 'Alt + N', '标记片头 / 片尾' },
    { 'F7 / F8', '播放列表 / 章节' },
    { 'F10 / F6', '音轨 / 字幕' },
    { 'F11', '全屏切换' },
    { 'Tab', '显示 / 隐藏界面' },
    { 'Esc', '关闭菜单 / 返回' },
    { '1 – 9', '跳转到 10% – 90%' },
  }
  local pw, ph = 1180, 120 + math.ceil(#lines / 2) * 44
  local px, py = (W - pw) / 2, (H - ph) / 2
  parts[#parts + 1] = rect(px, py, pw, ph, 30, BLACK, 0xF4)
  parts[#parts + 1] = text(px + 40, py + 32, 34, WHITE, 0x00, '键盘快捷键', 7, true)
  parts[#parts + 1] = text(px + pw - 40, py + 40, 20, DIM, 0x00, '任意键关闭', 9, false)
  local half = math.ceil(#lines / 2)
  for i, line in ipairs(lines) do
    local col = i <= half and 0 or 1
    local row = col == 0 and i or (i - half)
    local x = px + 40 + col * (pw / 2)
    local y = py + 104 + (row - 1) * 44
    parts[#parts + 1] = text(x, y, 21, WHITE, 0x00, line[1], 7, true, MONO)
    parts[#parts + 1] = text(x + 230, y, 21, GREY, 0x00, line[2], 7, false)
  end
end

local function draw_menu(parts)
  local menu = state.menu
  if not menu then
    return
  end
  local rows = menu.rows
  local function row_h(row)
    return row.kind == 'header' and 40 or ROW_H
  end

  -- Window the list around the selection so a 40-chapter file never pushes the
  -- panel off the top of the screen.
  local budget = 620
  local first, last, used = menu.index, menu.index, 0
  local i = menu.index
  while i >= 1 and used + row_h(rows[i]) <= budget do
    used = used + row_h(rows[i])
    first = i
    i = i - 1
  end
  local j = menu.index + 1
  while j <= #rows and used + row_h(rows[j]) <= budget do
    used = used + row_h(rows[j])
    last = j
    j = j + 1
  end

  local height = 62 + used + 20
  local left = RIGHT - MENU_W
  local top = MENU_BOTTOM - height

  parts[#parts + 1] = rect(left, top, MENU_W, height, 18, BLACK, 0xF2)
  parts[#parts + 1] = rect(left + 24, top + 46, MENU_W - 48, 1, 0, WHITE, 0x1E)
  parts[#parts + 1] = text(left + 28, top + 18, 22, DIM, 0x00, menu.title, 7, true)
  local count = 0
  for _, row in ipairs(rows) do
    if row.kind ~= 'header' then
      count = count + 1
    end
  end
  local marker = tostring(count) .. ' 项'
  parts[#parts + 1] = text(left + MENU_W - 28, top + 20, 18, DIM, 0x00, marker, 9, false)

  local y = top + 62
  for k = first, last do
    local row = rows[k]
    if row.kind == 'header' then
      parts[#parts + 1] = text(left + 28, y + 10, 17, DIM, 0x00, row.label, 7, true)
      y = y + 40
    else
      local selected = (k == menu.index)
      local hovered = state.hover == ('row:' .. tostring(k))
      if selected then
        -- A washed accent plate plus a 4 px spine instead of a solid white bar:
        -- the white bar was the most jarring thing next to the Dart chrome,
        -- and black-on-white also flipped the panel's own ink convention.
        parts[#parts + 1] = rect(left + 12, y + 4, MENU_W - 24, ROW_H - 8, 12, HDR_GOLD, 0x2E)
        parts[#parts + 1] = rect(left + 12, y + 10, 4, ROW_H - 20, 2, HDR_GOLD, 0xE6)
      elseif hovered then
        parts[#parts + 1] = rect(left + 12, y + 4, MENU_W - 24, ROW_H - 8, 12, WHITE, 0x14)
      end
      local fg = WHITE
      local dim = selected and GREY or DIM
      local label = clip(row.label or '', 26)
      if row.active and not selected then
        parts[#parts + 1] = rect(left + 24, y + ROW_H / 2 - 3, 6, 6, 3, WHITE, 0xFF)
      end
      local tx = left + 28
      if row.active and not selected then
        tx = left + 42
      end
      parts[#parts + 1] = text(tx, y + 18, 22, fg, 0x00, label, 7, row.active)
      local vx = left + MENU_W - 28
      if row.kind == 'adjust' then
        vx = vx - 46
      end
      if row.value then
        parts[#parts + 1] = text(vx, y + 19, 20, dim, 0x00, row.value, 9, false)
      end
      if row.kind == 'adjust' then
        parts[#parts + 1] = text(left + MENU_W - 28, y + 19, 16,
          selected and GREY or DIM, 0x00, '← →', 9, false)
      end
      add_hit({
        id = 'row:' .. tostring(k),
        x = left + 12,
        y = y,
        w = MENU_W - 24,
        h = ROW_H,
        onClick = function()
          menu.index = k
          activate_row()
        end,
      })
      y = y + ROW_H
    end
  end
end

local function draw_controls(parts)
  local row_top = CTRL_Y + (CTRL_H - 44) / 2

  -- Play / pause.
  local play_hover = state.hover == 'button:play'
  parts[#parts + 1] = rect(SAFE, row_top, 52, 44, 12, WHITE, play_hover and 0x2A or 0x00)
  if state.paused then
    parts[#parts + 1] = triangle(SAFE + 17, row_top + 10, 24, 'right', WHITE, 0xFF)
  else
    parts[#parts + 1] = rect(SAFE + 17, row_top + 10, 7, 24, 2, WHITE, 0xFF)
    parts[#parts + 1] = rect(SAFE + 28, row_top + 10, 7, 24, 2, WHITE, 0xFF)
  end
  add_hit({ id = 'button:play', x = SAFE, y = row_top, w = 52, h = 44, onClick = toggle_pause })

  local x = SAFE + 62
  draw_bar_button(parts, '-10', x, row_top, 58, 44, false, state.hover == 'button:-10', function()
    seek_rel(-10)
  end)
  x = x + 66
  draw_bar_button(parts, '+10', x, row_top, 58, 44, false, state.hover == 'button:+10', function()
    seek_rel(10)
  end)
  x = x + 74

  -- Time.
  local dur_text = state.duration > 0 and fmt_time(state.duration) or 'LIVE'
  parts[#parts + 1] = text(x, row_top + 12, 21, WHITE, 0x00, fmt_time(state.position), 7, true, MONO)
  local pos_w = measure(fmt_time(state.position), 21)
  parts[#parts + 1] = text(x + pos_w + 8, row_top + 12, 21, DIM, 0x00, '/ ' .. dur_text, 7, false, MONO)

  -- Right cluster.
  local buttons = {
    { label = '音轨', menu = 'audio' },
    { label = '字幕', menu = 'subtitle' },
    { label = '章节', menu = 'chapters' },
    { label = '速度', menu = 'speed' },
    { label = '列表', menu = 'playlist' },
    { label = '画面', menu = 'video' },
    { label = '统计', menu = 'stats' },
    { label = '更多', menu = 'more' },
  }
  local size = 21
  local gap = 6
  local widths = {}
  local total = 0
  for i, button in ipairs(buttons) do
    widths[i] = button_width(button.label, size)
    total = total + widths[i] + (i > 1 and gap or 0)
  end
  local bx = RIGHT - total
  for i, button in ipairs(buttons) do
    local active = (state.menu and state.menu.id == button.menu)
      or (button.menu == 'stats' and state.stats)
    draw_bar_button(parts, button.label, bx, row_top, widths[i], 44, active,
      state.hover == ('button:' .. button.label), function()
        open_menu(button.menu)
      end)
    bx = bx + widths[i] + gap
  end
end

--- Badge row: pills, not a dot-separated string.
---
--- The reference build lights up the formats it is actually delivering; the
--- same information as one grey text line reads as a log dump. Three tiers:
--- a fact gets a barely-there plate, a lit format gets a tinted plate plus an
--- accent ring and a full-strength label, and a format the chain is *not*
--- delivering gets an outline with a dimmed label. That keeps "the file has
--- DTS-HD MA" visibly apart from "DTS-HD MA is leaving over HDMI".
local function draw_badges(parts, x, y)
  local pad, gap, hgt, size = 11, 7, 28, 17
  local seen = {}
  for _, item in ipairs(badge_items()) do
    -- `video-format` and `hwdec-current` can both resolve to "D3D11"; showing
    -- the same pill twice wastes the row.
    if not seen[item.text] then
      seen[item.text] = true
      local bw = measure(item.text, size) + pad * 2
      local base = y + 6
      if item.tier == 'lit' then
        parts[#parts + 1] = rect(x, y, bw, hgt, hgt / 2, item.color, 0x40)
        parts[#parts + 1] = rect_line(x, y, bw, hgt, hgt / 2, item.color, 0xB4, 1.2)
        -- `text()` takes the ASS alpha (0 = opaque), unlike `rect()` which takes
        -- an opacity. 0x00 here, not 0xFF.
        parts[#parts + 1] = text(x + pad, base, size, item.color, 0x00, item.text, 7, true, MONO)
      elseif item.tier == 'dim' then
        -- A ring this faint vanishes over dark footage, which left the row
        -- looking ragged: one label floating with no pill around it.
        parts[#parts + 1] = rect_line(x, y, bw, hgt, hgt / 2, DIM, 0x8C, 1.1)
        parts[#parts + 1] = text(x + pad, base, size, DIM, 0x00, item.text, 7, false, MONO)
      else
        parts[#parts + 1] = rect(x, y, bw, hgt, hgt / 2, WHITE, 0x14)
        parts[#parts + 1] = text(x + pad, base, size, item.color, 0x18, item.text, 7, false, MONO)
      end
      x = x + bw + gap
    end
  end
end

local function draw_chrome(parts)
  local title = state.title ~= '' and state.title or state.fallback_title
  title = clip(title, 56)
  parts[#parts + 1] = text(SAFE, TITLE_Y, 40, WHITE, 0x00, title, 7, true)

  draw_badges(parts, SAFE, META_Y - 12)

  local chapter_name = nil
  if state.chapter and state.chapters[state.chapter + 1] then
    chapter_name = state.chapters[state.chapter + 1].title
  end
  if chapter_name and chapter_name ~= '' then
    parts[#parts + 1] = text(RIGHT, META_Y, 20, DIM, 0x00, clip(chapter_name, 30), 9, false)
  end

  parts[#parts + 1] = text(
    SAFE, HINT_Y, 16, DIM, 0x00,
    '空格 暂停   ←→ 快退/快进   ↑↓ 音量   Tab 隐藏界面   H 快捷键   Esc 返回',
    7, false
  )
end

--- `startup_format_logos.lua` owns the light-up badging; the OSD keeps only
--- the always-on pill row above the progress bar.

function render()
  hits = {}

  if state.help then
    local parts = {}
    draw_help(parts)
    osd.data = table.concat(parts, '\n')
    osd:update()
    return
  end

  if not state.visible then
    -- A toast still needs to be readable with the chrome hidden (volume, seek).
    if state.toast then
      local parts = {}
      draw_toast(parts)
      osd.data = table.concat(parts, '\n')
      osd:update()
    else
      osd.data = ''
      osd:remove()
    end
    return
  end

  local parts = {}

  -- When the Dart side owns the chrome (user-data/player/osd-engine ==
  -- 'window'), the bottom band is not drawn here at all: the independent
  -- layered window composites it as plain 8-bit SDR, which a PQ swapchain
  -- cannot darken. Menus, stats, help and toasts are centre/overlay surfaces
  -- that stay in mpv so the whole interaction model does not have to move.
  -- Audio-only files keep the full Lua stage: there is no picture to protect,
  -- and the audio stage carries its own controls.
  local dart_chrome = not state.audio_mode
    and (state.chrome_window
      or mp.get_property('user-data/player/osd-engine') == 'window')

  if state.audio_mode then
    -- No video: paint our own stage, but keep the transport bar usable.
    draw_audio_stage(parts)
  elseif not dart_chrome then
    draw_scrim(parts)
    draw_chrome(parts)
  end

  if state.stats then
    draw_stats(parts)
  end

  if not dart_chrome then
    draw_progress(parts)
    draw_controls(parts)
  end

  -- The menu moved to the Dart layer when it owns the chrome: it pushed the
  -- model through `push_menu`, and drawing it here as well would stack two
  -- panels with two different hit maps.
  if state.menu and not dart_chrome then
    draw_menu(parts)
  end

  draw_toast(parts)

  osd.data = table.concat(parts, '\n')
  osd:update()
end

-- ==== VISIBILITY ===========================================================

function schedule_hide()
  if hide_timer then
    hide_timer:kill()
    hide_timer = nil
  end
  if state.paused or state.menu or state.stats or state.audio_mode or state.help then
    return
  end
  hide_timer = mp.add_timeout(AUTOHIDE, function()
    hide_timer = nil
    -- Re-check: the timer may have been scheduled before a menu or the stats
    -- panel opened, and those must never auto-hide.
    if state.menu or state.stats or state.audio_mode or state.help or state.paused then
      return
    end
    state.visible = false
    render()
  end)
end

function show_ui()
  state.visible = true
  mark_dirty()
  render()
end

local function show()
  if state.help then
    return
  end
  show_ui()
  schedule_hide()
end

local function toggle_ui()
  if state.visible and not state.menu then
    state.visible = false
    if hide_timer then
      hide_timer:kill()
      hide_timer = nil
    end
    render()
  else
    show()
  end
end

function send_back()
  seq = seq + 1
  mp.commandv('script-message', 'player-event', utils.format_json({ type = 'back', seq = seq }))
end

-- Flutter owns the real window, so this is a request rather than a command:
-- the host toggles the window state and re-fits the native surface afterwards.
function send_fullscreen()
  seq = seq + 1
  mp.commandv('script-message', 'player-event', utils.format_json({ type = 'fullscreen', seq = seq }))
end

-- ==== INPUT ================================================================

local function handle_key(raw)
  local name, mods = esc_key_name(raw)
  local shift = has_mod(mods, 'shift')
  local alt = has_mod(mods, 'alt')
  local ctrl = has_mod(mods, 'ctrl')

  if state.help then
    state.help = false
    mark_dirty()
    render()
    return
  end

  if state.menu then
    if name == 'esc' or name == 'tab' then
      close_menu()
      return
    elseif name == 'up' then
      menu_move(-1)
      return
    elseif name == 'down' then
      menu_move(1)
      return
    elseif name == 'enter' then
      activate_row()
      return
    elseif name == 'left' then
      adjust_row(-1)
      return
    elseif name == 'right' then
      adjust_row(1)
      return
    else
      close_menu()
      -- fall through to the global map
    end
  end

  if name == 'esc' then
    -- Heartbeat so Flutter knows the script is alive and must not apply its own
    -- "Esc closes the player" fallback.
    seq = seq + 1
    mp.commandv('script-message', 'player-event', utils.format_json({ type = 'ui', seq = seq }))
    if state.stats then
      state.stats = false
      mark_dirty()
      render()
    elseif state.visible then
      state.visible = false
      render()
    else
      send_back()
    end
  elseif name == 'tab' then
    toggle_ui()
  elseif name == 'space' or name == 'k' then
    -- Space is pause everywhere, even with the chrome hidden: it is the key
    -- people press without looking.
    toggle_pause()
    if not state.visible then
      show()
    end
  elseif name == 'left' then
    -- Tap to nudge, keep tapping to climb. The first rung matches PsSeek.step
    -- in lib/design/ps_media.dart and Shift matches PsSeek.jump: change them
    -- here and there, never here alone.
    seek_step(-1, shift and SEEK_JUMP or SEEK_NUDGE, shift and 'jump' or 'nudge')
  elseif name == 'right' then
    seek_step(1, shift and SEEK_JUMP or SEEK_NUDGE, shift and 'jump' or 'nudge')
  elseif name == 'up' then
    add_volume(5)
  elseif name == 'down' then
    add_volume(-5)
  elseif name == 'm' then
    toggle_mute()
  elseif name == 'j' then
    cycle_track('sub', shift and -1 or 1)
  elseif name == 'v' then
    toggle_sub_visibility()
  elseif name == 'z' then
    adjust_sub_delay(-0.1)
  elseif name == 'x' then
    adjust_sub_delay(0.1)
  elseif name == 'a' then
    cycle_track('audio', shift and -1 or 1)
  elseif name == '[' then
    speed_ratio(0.9091)
  elseif name == ']' then
    speed_ratio(1.1)
  elseif name == 'bs' then
    set_speed(1.0)
  elseif name == 's' then
    screenshot(shift)
  elseif name == 'i' then
    state.stats = not state.stats
    show_ui()
    mark_dirty()
  elseif name == 'c' then
    local list = state.chapters
    if #list == 0 then
      toast('这个文件没有章节')
    else
      local index = (state.chapter + 1) % #list + 1
      local chapter = list[index]
      seek_abs(chapter.time or 0)
      toast('章节：' .. (chapter.title or tostring(index)))
    end
  elseif name == 'l' then
    cycle_loop()
  elseif name == 'n' then
    if alt then
      mark_segment('intro')
    else
      command('playlist-next', 'force')
    end
  elseif name == 'e' and alt then
    mark_segment('outro')
  elseif name == 'o' and alt then
    -- Flutter owns the file dialog; the OSD cannot open one.
    seq = seq + 1
    mp.commandv('script-message', 'player-event', utils.format_json({ type = 'subtitle', seq = seq }))
  elseif name == 'b' and alt then
    command('playlist-prev')
  elseif name == 'b' and ctrl then
    -- Ctrl+B is the reference build's CreateBookmark (keyboard.xml:457). It
    -- toggles here rather than only adding, because there is no bookmark
    -- window to delete from.
    toggle_bookmark()
  elseif name == 'pageup' then
    command('playlist-prev')
  elseif name == 'pagedown' then
    command('playlist-next', 'force')
  elseif name == 'comma' then
    if state.paused then
      frame_step(-1)
    end
  elseif name == 'period' then
    if state.paused then
      frame_step(1)
    end
  elseif name == 'f7' then
    open_menu('playlist')
  elseif name == 'f8' then
    open_menu('chapters')
  elseif name == 'f9' then
    open_menu('video')
  elseif name == 'f10' then
    open_menu('audio')
  elseif name == 'f6' then
    open_menu('subtitle')
  elseif name == 'f11' then
    send_fullscreen()
  elseif name == 'h' then
    state.help = true
    mark_dirty()
    render()
  elseif name:match('^%d$') then
    local percent = tonumber(name) * 10
    if state.duration > 0 then
      seek_abs(state.duration * percent / 100)
    end
  end
end

-- Bind inside mpv too: whichever window holds the keyboard, exactly one
-- handler runs. Names must match the ones Flutter forwards ("shift+left").
local BINDINGS = {
  { 'SPACE', 'space' }, { 'LEFT', 'left' }, { 'RIGHT', 'right' },
  { 'UP', 'up' }, { 'DOWN', 'down' },
  { 'Shift+LEFT', 'shift+left' }, { 'Shift+RIGHT', 'shift+right' },
  { 'j', 'j' }, { 'J', 'shift+j' },
  { 'z', 'z' }, { 'x', 'x' },
  { 'a', 'a' }, { 'A', 'shift+a' },
  { 'm', 'm' }, { 'i', 'i' }, { 'I', 'i', 'shift-i' },
  { 's', 's' }, { 'S', 'shift+s' },
  { 'v', 'v' }, { 'c', 'c' }, { 'l', 'l' }, { 'h', 'h' },
  { 'TAB', 'tab' }, { 'ESC', 'esc' },
  { 'PGUP', 'pageup' }, { 'PGDWN', 'pagedown' }, { 'BS', 'bs' },
  { '[', '[' }, { ']', ']' }, { ',', 'comma' }, { '.', 'period' },
  { 'F7', 'f7' }, { 'F8', 'f8' }, { 'F9', 'f9' },
  { 'F6', 'f6' }, { 'F10', 'f10' }, { 'F11', 'f11' },
  { 'Alt+n', 'alt+n' },
  { 'Alt+e', 'alt+e' },
  { 'Alt+o', 'alt+o' },
  { 'Ctrl+b', 'ctrl+b' },
  { '1', '1' }, { '2', '2' }, { '3', '3' }, { '4', '4' }, { '5', '5' },
  { '6', '6' }, { '7', '7' }, { '8', '8' }, { '9', '9' },
}

for _, entry in ipairs(BINDINGS) do
  local binding, name = entry[1], entry[2]
  -- Binding names must be unique: `i` and `I` share a handler but not an id.
  local id = entry[3] or name
  mp.add_key_binding(binding, 'pp-' .. id:gsub('%+', '-'), function()
    handle_key(name)
  end)
end

-- Mouse buttons are bound in the MOUSE section below, as one key-binding
-- group with proper down/up pairs. Binding MBTN_LEFT here with
-- `add_key_binding` gave a single press event, so the progress bar could never
-- be dragged and a click fired even when the pointer had slid off the control.

-- ==== MOUSE ================================================================

--- Maps window pixels into the 1920x1080 design space.
---
--- mpv renders an `ass-events` overlay into the *whole* OSD frame: the only
--- geometry call in `sub/osd_libass.c` is
--- `ass_set_frame_size(render, res->w, res->h)` — there is no
--- `ass_set_margins`. libass therefore stretches PlayResX/Y across the full
--- client area, independently per axis, and `osd-dimensions.w/h` are exactly
--- that area. The picture's letterbox margins (`dim.ml/mt/mr/mb`) describe
--- where the video sits *inside* the frame; they never move the overlay.
---
--- Subtracting those margins — which this function used to do — shifted every
--- hit box by half the letterbox, which is why the seek bar only answered when
--- the pointer was aimed away from it. The scale has to be window/W.
local function to_design(mx, my)
  local dim = mp.get_property_native('osd-dimensions')
  if dim and dim.w and dim.w > 0 and dim.h and dim.h > 0 then
    return mx * W / dim.w, my * H / dim.h
  end
  return mx, my
end

--- Current pointer position in design space, or nil when nobody knows it.
---
--- Two sources, and the forwarded one wins. mpv's own `mouse-pos` never updates
--- in this embedding: the picture is a native child window owned by the host,
--- and Windows delivers the mouse messages to the Flutter view instead (the mpv
--- log contains no `[input]` line at all for a whole session). The host
--- therefore forwards normalized coordinates over `player-cmd`, and this is the
--- single place both paths converge — every hit test and every drag reads the
--- same numbers, no matter which side produced them.
---
--- Returns two values, so callers must use multiple assignment. Assigning the
--- result to one variable silently kept only `x`, and the very first real click
--- would have died on `attempt to index a number value`.
local function pointer_design()
  local forwarded = state.pointer
  if state.external_pointer and forwarded then
    return forwarded.x, forwarded.y
  end
  local pos = mp.get_property_native('mouse-pos')
  if not pos or not pos.x then
    return nil
  end
  return to_design(pos.x, pos.y)
end

local drag_bar = false

--- Seek by dragging the progress bar. `absolute` (not `exact`) keeps the
--- preview responsive; the final position is committed on release.
local function bar_seek(x)
  if not state.duration or state.duration <= 0 then
    return
  end
  local ratio = math.max(0, math.min(1, (x - SAFE) / (W - SAFE * 2)))
  command('seek', string.format('%.3f', state.duration * ratio), 'absolute')
  state.position = state.duration * ratio
  mark_dirty()
end

--- Re-runs hit testing and repaints when the hovered control changed.
local function update_hover(x, y)
  local hit = hit_at(x, y)
  local id = hit and hit.id or nil
  if id ~= state.hover then
    state.hover = id
    mark_dirty()
    render()
  end
  return hit
end

--- Repaint cadence for anything that follows the pointer.
---
--- `mark_dirty()` is flushed by the 100 ms tick, which is right for a progress
--- bar and wrong for the pointer: the scrub preview, the hover lift and a bar
--- being dragged would all trail by up to a tenth of a second — which is what
--- "the OSD lags when I use the mouse" was.
---
--- Coalescing to 30 Hz keeps it visually continuous without re-emitting the
--- whole ASS blob once per mouse packet (a 1000 Hz mouse would otherwise ask
--- for a thousand IPC round-trips a second).
local POINTER_INTERVAL = 1 / 30
local pointer_frame = false

local function paint_pointer()
  if pointer_frame then
    return
  end
  pointer_frame = true
  mp.add_timeout(POINTER_INTERVAL, function()
    pointer_frame = false
    -- Re-checked at fire time: the chrome may have auto-hidden in between, and
    -- painting a removed overlay would pop it back for one frame.
    if state.visible or state.help or state.toast then
      render()
    end
  end)
end

mp.observe_property('mouse-pos', 'native', function(_, value)
  -- The host owns pointer input here; anything mpv might report on its own is
  -- stale by definition and would fight the forwarded position.
  if state.external_pointer then
    return
  end
  if not value or not value.x then
    state.pointer = nil
    state.hover = nil
    return
  end
  if value.hover == false then
    -- The pointer left our surface — still proof that mpv receives mouse input.
    state.mouse_seen = true
    state.pointer = nil
    state.hover = nil
    mark_dirty()
    return
  end
  local x, y = to_design(value.x, value.y)
  state.pointer = { x = x, y = y }
  state.mouse_seen = true

  if drag_bar then
    bar_seek(x)
    -- Dragging is still "using" the bar, so the auto-hide clock restarts; a
    -- slow scrub would otherwise pop the chrome away under the pointer.
    schedule_hide()
    return
  end

  update_hover(x, y)
  if state.visible then
    schedule_hide()
    if state.hover then
      paint_pointer()
    end
  else
    -- Moving the mouse brings the chrome back, the way every desktop player
    -- does it. mouse-pos only fires on real movement.
    show()
  end
end)

-- Clicking, dragging and wheeling.
--
-- Drawing alone made the bar inert: the script tracked `mouse-pos` for hover
-- but never bound a mouse button, so every click fell through to mpv's default
-- bindings (and `input-default-bindings=no` meant there were none). uosc solves
-- this the same way — bind `mbtn_left`, read `mouse-pos` on press, and resolve
-- the hitboxes recorded by the last render.
local function on_primary_down()
  local px, py = pointer_design()
  if not px then
    return
  end
  -- Remembered before `show()`: a click on a hidden UI must only bring the
  -- chrome back, never reach the control that happened to be under the cursor
  -- (or toggle it straight back off).
  local was_visible = state.visible
  show()
  local hit = update_hover(px, py)
  -- The comment above is a promise the code has to keep: when the chrome was
  -- hidden, the press only reveals it. Without this the first click on an empty
  -- patch of video still armed whichever button happened to be under the
  -- pointer, and released it a moment later.
  if not was_visible then
    hit = nil
  end
  state.press = {
    id = hit and hit.id or nil,
    x = px,
    y = py,
    at = now(),
    was_visible = was_visible,
  }
  if hit and hit.id == 'bar' then
    drag_bar = true
    bar_seek(px)
  end
end

local function on_primary_up()
  local press = state.press
  state.press = nil
  if drag_bar then
    drag_bar = false
    local px = pointer_design()
    if px then
      bar_seek(px)
    end
    return
  end
  if not press or not press.id then
    -- Empty space: close a menu; otherwise toggle the chrome — but only if the
    -- chrome was already up when the button went down.
    if state.menu then
      close_menu()
    elseif press and press.was_visible then
      toggle_ui()
    else
      show()
    end
    return
  end
  -- A click only counts when the pointer comes up over the same control it
  -- went down on, so a press-and-slide off a button does not fire it. The test
  -- is made against where the pointer *is now* — testing the press position
  -- would make press-then-drag-away-release still fire the button.
  local ux, uy = pointer_design()
  if not ux then
    ux, uy = press.x, press.y
  end
  local hit = hit_at(ux, uy)
  if hit and hit.id == press.id and hit.onClick and (now() - press.at) < 1.2 then
    hit.onClick()
    mark_dirty()
    render()
    return
  end
  if state.menu then
    close_menu()
  end
end

local function on_secondary_down()
  if not close_menu() then
    if state.visible then
      open_menu('more')
    else
      show()
    end
  end
end

--- Window-normalized coordinates (0..1) into the 1920x1080 design space.
---
--- The exact inverse of [to_design]: the host's widget is the same rectangle
--- mpv calls the OSD frame, so the mapping is a plain scale, nx*W and ny*H.
--- It must never consult `osd-dimensions.margins` — those describe the picture,
--- not the overlay, and folding them in here is what made a forwarded click
--- land on a different control than the one under the cursor.
local function unit_to_design(nx, ny)
  return nx * W, ny * H
end

--- Pointer events forwarded by the host.
---
--- `ev` is `move`, `down`, `up` or `wheel`; `button` is `left`/`right`; `delta`
--- is +1/-1 for wheels. Coordinates are normalized against the whole window,
--- the same space the OSD is rendered in, so the host never has to model the
--- 1920x1080 design space — the moment two places both "know" the layout they
--- start disagreeing, and the symptom is controls that highlight one place and
--- act in another.
local function handle_mouse(payload)
  state.external_pointer = true
  state.mouse_seen = true
  state.mouse_events = state.mouse_events + 1

  local nx = tonumber(payload.nx)
  local ny = tonumber(payload.ny)
  if nx and ny then
    local x, y = unit_to_design(nx, ny)
    state.pointer = { x = x, y = y }
  end

  local ev = payload.ev
  if ev == 'move' then
    if drag_bar then
      -- Dragging is still "using" the bar, so the auto-hide clock restarts; a
      -- slow scrub would otherwise pop the chrome away under the pointer.
      local x = pointer_design()
      if x then
        bar_seek(x)
      end
      schedule_hide()
      paint_pointer()
      return
    end
    local x, y = pointer_design()
    if not x then
      return
    end
    update_hover(x, y)
    if state.visible then
      schedule_hide()
      -- Only controls react to the pointer. Over bare video nothing moves, and
      -- repainting there would be work with no visible change.
      if state.hover then
        paint_pointer()
      end
    else
      show()
    end
  elseif ev == 'down' then
    if payload.button == 'right' then
      on_secondary_down()
    else
      on_primary_down()
    end
  elseif ev == 'up' then
    -- Only the left button has a press/release pair here. A right-click opens
    -- the menu on press, so forwarding its release would land in
    -- `on_primary_up` and close the menu that was just opened.
    if payload.button ~= 'right' then
      on_primary_up()
    end
  elseif ev == 'wheel' then
    local delta = tonumber(payload.delta) or 0
    if delta ~= 0 then
      if state.menu then
        menu_move(delta > 0 and -1 or 1)
      else
        add_volume(delta > 0 and 5 or -5)
      end
    end
  end
end

-- No `mbtn_*` bindings here on purpose.
--
-- Two reasons, both observed rather than assumed:
--
--   1. mpv never delivers mouse events in this embedding. A whole session's log
--      has no `[input]` line: the picture is a native child window owned by the
--      host, and Windows hands the mouse messages to the Flutter view.
--   2. Even when it does, a binding cannot express "button released" in a way
--      this mpv build reports — the section it generates contains a single
--      `mbtn_left script-binding` line and no release counterpart. A seekbar
--      press would therefore start a drag that never ends, pinning the playhead
--      to the pointer.
--
-- So the host owns pointer input and sends `mouse` commands; the observer above
-- is only a fallback for running this script in a plain mpv.
mp.set_key_bindings({
  -- Double click must not reach mpv: it would toggle fullscreen behind our back.
  { 'mbtn_left_dbl', 'ignore' },
}, 'xnx-mouse', 'force')
mp.enable_key_bindings('xnx-mouse')

-- ==== IPC ==================================================================

mp.register_script_message('player-cmd', function(json)
  local ok, payload = pcall(utils.parse_json, json)
  if not ok or type(payload) ~= 'table' then
    msg.debug('bad command: ' .. tostring(json))
    return
  end
  local cmd = payload.cmd
  if cmd == 'show' then
    show()
  elseif cmd == 'hide' then
    state.visible = false
    render()
  elseif cmd == 'chrome' then
    -- The host asks who draws the bottom band. Answering is what lets Dart
    -- start painting only after the hand-off is real; a swallowed message
    -- would otherwise leave two engines believing they own it.
    state.chrome_window = payload.mode == 'window'
    mark_dirty()
    render()
    mp.commandv('script-message', 'player-event', utils.format_json({
      type = 'chrome',
      mode = state.chrome_window and 'window' or 'lua',
    }))
  elseif cmd == 'redraw' then
    -- Window resized: rebuild the overlay for the new OSD frame without
    -- touching visibility. The hit boxes live in design space, so this is
    -- purely about the pixels matching the new scale.
    mark_dirty()
    if state.visible or state.menu or state.stats or state.help or state.toast then
      render()
    end
  elseif cmd == 'key' and payload.key then
    handle_key(payload.key)
  elseif cmd == 'title' then
    state.title = payload.title or ''
    mark_dirty()
  elseif cmd == 'toast' then
    toast(payload.text or '')
  elseif cmd == 'menu' and payload.id then
    open_menu(payload.id)
  elseif cmd == 'menu-op' then
    -- Forwarded from the Dart panel: it draws and hit-tests, this side owns
    -- what each row does.
    local op = payload.op
    local menu = state.menu
    if op == 'close' then
      close_menu()
    elseif menu and op == 'move' then
      local target = tonumber(payload.index)
      if target then
        menu.index = math.max(1, math.min(#menu.rows, math.floor(target)))
        mark_dirty()
      end
    elseif menu and op == 'choose' then
      local target = tonumber(payload.index)
      if target then
        menu.index = math.max(1, math.min(#menu.rows, math.floor(target)))
      end
      activate_row()
    elseif menu and op == 'adjust' then
      adjust_row((tonumber(payload.direction) or 1) < 0 and -1 or 1)
    end
  elseif cmd == 'mouse' then
    handle_mouse(payload)
  end
end)

-- ==== LIFECYCLE ============================================================

local function refresh_menu()
  if state.menu then
    local keep = state.menu.index
    state.menu.rows = build_menu(state.menu.id)
    state.menu.index = math.min(keep, #state.menu.rows)
  end
end

mp.observe_property('time-pos', 'number', function(_, value)
  state.position = tonumber(value) or 0
  mark_dirty()
  -- Cuts and mutes are evaluated here rather than on a timer: this fires for
  -- playback progress *and* for seeks, which are the only two ways the playhead
  -- can arrive inside a marked region.
  apply_edits()
end)

mp.observe_property('duration', 'number', function(_, value)
  state.duration = tonumber(value) or 0
  mark_dirty()
end)

mp.observe_property('demuxer-cache-time', 'number', function(_, value)
  state.buffer = tonumber(value) or 0
  mark_dirty()
end)

mp.observe_property('pause', 'bool', function(_, value)
  state.paused = value == true
  if state.paused then
    if hide_timer then
      hide_timer:kill()
      hide_timer = nil
    end
    show_ui()
  else
    mark_dirty()
    schedule_hide()
  end
end)

mp.observe_property('media-title', 'string', function(_, value)
  state.fallback_title = value or ''
  mark_dirty()
end)

mp.observe_property('user-data/player/title', 'string', function(_, value)
  state.title = value or ''
  mark_dirty()
end)

mp.observe_property('chapter-list', 'native', function(_, value)
  state.chapters = type(value) == 'table' and value or {}
  invalidate_edits()
  mark_dirty()
  refresh_menu()
end)

mp.observe_property('chapter', 'number', function(_, value)
  state.chapter = tonumber(value) or -1
  mark_dirty()
end)

mp.observe_property('track-list', 'native', function(_, value)
  local list = type(value) == 'table' and value or {}
  if #list == 0 then
    -- Nothing loaded yet: do not mistake "no tracks" for an audio-only file.
    return
  end
  local has_video = false
  for _, track in ipairs(list) do
    if track.type == 'video' and track.selected ~= false then
      has_video = true
    end
  end
  state.has_video = has_video
  state.audio_mode = not has_video
  if state.audio_mode and not state.visible then
    show_ui()
  end
  refresh_menu()
  mark_dirty()
end)

mp.observe_property('speed', 'number', function()
  refresh_menu()
  mark_dirty()
end)

--- Watches a track switch for a silent audio chain, and rebuilds the AO when
--- the new track never starts.
---
--- Reported on real hardware: TrueHD → AC-3 switches, and back, left playback
--- running with no sound at all — the old track was not restorable either. The
--- log shows the switch never reaches a fresh AO init; the chain dies on the
--- layout change (8ch → 6ch on a virtualized device) and mpv does not retry.
--- The tell is `audio-pts` frozen while the video clock advances. A dead chain
--- is rebuilt by switching the aid off and straight back on, which forces mpv
--- to uninit and reinit the AO — the same recovery a manual `aid=no` toggle
--- performs.
local audio_watch = nil

local function watch_audio_recovery(new_aid)
  if audio_watch then
    audio_watch:kill()
    audio_watch = nil
  end
  if new_aid == nil or new_aid == 'no' then
    return
  end
  -- Silence while paused is normal; only a playing chain can die.
  audio_watch = mp.add_timeout(1.0, function()
    audio_watch = nil
    if mp.get_property_bool('pause') then
      return
    end
    local pts = mp.get_property_number('audio-pts')
    local video = mp.get_property_number('video-pts')
    if pts == nil or video == nil or pts > 0 then
      return
    end
    -- Two samples a half second apart: audio genuinely stuck while video runs.
    local second = mp.add_timeout(0.5, function()
      audio_watch = nil
      local pts2 = mp.get_property_number('audio-pts')
      local video2 = mp.get_property_number('video-pts')
      if pts2 == nil or video2 == nil then
        return
      end
      if pts2 > (pts or 0) or video2 <= (video or 0) then
        return
      end
      local frozen = new_aid
      toast('音频输出未响应，正在重建…')
      mp.commandv('set', 'aid', 'no')
      mp.add_timeout(0.15, function()
        mp.commandv('set', 'aid', frozen == 'auto' and 'auto' or frozen)
      end)
    end)
    audio_watch = second
  end)
end

mp.observe_property('aid', 'string', function(_, value)
  refresh_menu()
  mark_dirty()
  watch_audio_recovery(value)
end)

-- The Dart side flips this to 'window' when the independent OSD layer takes
-- over the bottom chrome, and back to 'mpv' when that layer is unavailable.
mp.observe_property('user-data/player/osd-engine', 'string', function(_, value)
  state.chrome_window = value == 'window'
  refresh_menu()
  mark_dirty()
  render()
end)

mp.observe_property('sid', 'string', function()
  refresh_menu()
  mark_dirty()
end)

mp.observe_property('playlist-pos', 'number', function()
  refresh_menu()
  mark_dirty()
end)

mp.observe_property('osd-dimensions', 'native', function()
  mark_dirty()
  render()
end)

mp.register_event('file-loaded', function()
  state.visible = true
  state.stats = false
  state.menu = nil
  state.help = false
  invalidate_edits()
  reset_edits()
  -- Before the first paint, so the ticks are there the moment the bar appears
  -- instead of popping in on the first redraw.
  refresh_bookmarks()
  mark_dirty()
  render()
  schedule_hide()
  -- The path is only authoritative once mpv has resolved it; a mark made before
  -- the first frame would otherwise be filed under the previous episode's key.
  mp.add_timeout(0.8, function()
    invalidate_edits()
    apply_edits()
  end)
end)

mp.register_event('end-file', function()
  state.menu = nil
  mark_dirty()
end)

mp.add_periodic_timer(TICK, function()
  if state.toast and state.toast.expires - now() <= 0 then
    state.toast = nil
    mark_dirty()
  end
  if dirty then
    dirty = false
    render()
  end
end)

render()
