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

local TITLE_Y = 790
local META_Y = 844
local BAR_Y = 884
local BAR_H = 4
local CTRL_Y = 902
local CTRL_H = 66
local HINT_Y = 992
local MENU_BOTTOM = 862
local MENU_W = 600
local ROW_H = 52
local AUTOHIDE = 4.5
local TICK = 0.1

local WHITE = '&HFFFFFF&'
local GREY = '&HBEBEBE&'
local DIM = '&H8C8C8C&'
local BLACK = '&H000000&'

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
local function rect(x, y, w, h, r, color, alpha)
  if w <= 0 or h <= 0 then
    return ''
  end
  local opacity = 0xFF - math.max(0, math.min(0xFF, round(alpha or 0)))
  return string.format(
    '{\\an7\\pos(%d,%d)\\p1\\bord0\\shad0\\1c%s\\1a&H%02X&}%s{\\p0}',
    round(x), round(y), color, opacity, rrect_path(w, h, r)
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
local function text(x, y, size, color, alpha, str, align, bold, font)
  return string.format(
    '{\\an%d\\pos(%d,%d)\\fn%s\\fs%d\\bord0\\shad0\\%s\\c%s\\1a&H%02X&}%s',
    align or 7, round(x), round(y), font or FONT, round(size),
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
  hover = nil,
  pointer = nil,
  menu = nil,
  stats = false,
  help = false,
  toast = nil,
  audio_mode = false,
  has_video = true,
  ui_scale = 1,
}

local seq = 0
local hide_timer = nil
local outro_skipped = false

-- Forward declarations. Lua locals are not hoisted: the menu section above the
-- render section calls back into it, so these names must exist first.
local mark_dirty, render, show_ui, schedule_hide, send_back, close_menu

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

local function file_key()
  local path = mp.get_property('path') or ''
  local _, name = utils.split_path(path)
  return name or path or ''
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

local function hdr_label()
  local prim = mp.get_property('video-params/primaries') or ''
  local gamma = mp.get_property('video-params/gamma') or ''
  local sig = mp.get_property('video-params/sig-peak')
  local is_hdr = (prim:find('bt.2020') or prim:find('2020')) ~= nil
    or (gamma:find('pq') or gamma:find('hlg') or gamma:find('st2084')) ~= nil
    or (tonumber(sig) or 0) > 100
  if not is_hdr then
    return nil
  end
  if gamma:find('hlg') then
    return 'HLG'
  end
  if prim:find('dolbyvision') then
    return 'DV'
  end
  local peak = tonumber(sig) or 0
  if peak >= 900 then
    return 'HDR10 ' .. round(peak) .. 'nits'
  end
  return 'HDR'
end

local function video_badges()
  local out = {}
  local w = mp.get_property_number('video-params/w') or 0
  local hgt = mp.get_property_number('video-params/h') or 0
  if w >= 7600 or hgt >= 4300 then
    table.insert(out, '8K')
  elseif w >= 3800 or hgt >= 2100 then
    table.insert(out, '4K')
  elseif w >= 1900 or hgt >= 1060 then
    table.insert(out, '1080p')
  elseif w > 0 then
    table.insert(out, tostring(w) .. 'x' .. tostring(hgt))
  end

  local codec = mp.get_property('video-format')
  local depth = mp.get_property_number('video-params/plane-depth')
  if codec then
    local label = codec:upper()
    if depth and depth > 8 then
      label = label .. ' ' .. tostring(round(depth)) .. 'bit'
    end
    table.insert(out, label)
  end

  local hdr = hdr_label()
  if hdr then
    table.insert(out, hdr)
  end

  local fps = mp.get_property_number('container-fps')
  if fps and fps > 0 then
    table.insert(out, string.format('%.3g fps', fps))
  end

  table.insert(out, hwdec_label(mp.get_property('hwdec-current')))

  local audio = mp.get_property('audio-codec-name')
  if audio then
    table.insert(out, audio:upper())
  end

  local rate = mp.get_property_number('file-size')
  local dur = state.duration
  if rate and dur and dur > 1 and rate > 0 then
    table.insert(out, string.format('%.1f Mbps', rate * 8 / dur / 1000000))
  end

  return table.concat(out, '  ·  ')
end

-- ==== SEGMENTS =============================================================

local SEG_CACHE = nil
local SEG_PATH = nil

local function segments_path()
  if SEG_PATH then
    return SEG_PATH
  end
  local base = os.getenv('APPDATA') or os.getenv('HOME') or '.'
  local dir = utils.join_path(base, 'XnX Player')
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

local function current_segment()
  local key = file_key()
  if key == '' then
    return nil
  end
  local all = load_segments()
  return all[key]
end

local function set_segment(slot, s, e)
  local key = file_key()
  if key == '' then
    return
  end
  local all = load_segments()
  local entry = all[key] or {}
  entry[slot] = { start = s, ['end'] = e }
  all[key] = entry
  SEG_CACHE = all
  save_segments()
end

local function clear_segment(slot)
  local key = file_key()
  local all = load_segments()
  local entry = all[key]
  if entry then
    entry[slot] = nil
    save_segments()
  end
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

--- Segments to honour: manual marks win, then chapter names.
local function effective_segments()
  local out = {}
  local stored = current_segment()
  if stored then
    for slot, pair in pairs(stored) do
      if type(pair) == 'table' and tonumber(pair['start']) and tonumber(pair['end']) then
        out[slot] = { start = tonumber(pair['start']), ['end'] = tonumber(pair['end']) }
      end
    end
  end
  for _, chapter in ipairs(state.chapters) do
    local slot = classify_chapter(chapter.title)
    if slot and not out[slot] and chapter.time then
      -- A chapter marker says where the segment starts; it ends where the
      -- following chapter starts.
      local next_time = nil
      for _, other in ipairs(state.chapters) do
        if other.time and other.time > chapter.time + 1 then
          if not next_time or other.time < next_time then
            next_time = other.time
          end
        end
      end
      if next_time then
        out[slot] = { start = chapter.time, ['end'] = next_time }
      end
    end
  end
  return out
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

local function mark_segment()
  local stored = current_segment() or {}
  local intro = stored['intro']
  local pos = state.position
  if not intro or not tonumber(intro['start']) then
    set_segment('intro', pos, nil)
    toast('片头起点已标记 ' .. fmt_time(pos) .. '，再按 Alt+N 标记终点')
  elseif not tonumber(intro['end']) then
    if pos <= tonumber(intro['start']) then
      toast('终点必须在起点之后')
      return
    end
    set_segment('intro', tonumber(intro['start']), pos)
    toast(string.format('片头 %s – %s 已保存', fmt_time(intro['start']), fmt_time(pos)))
  else
    clear_segment('intro')
    toast('片头标记已清除')
  end
end

local function maybe_skip(opening)
  local enabled = mp.get_property('user-data/xnx/skip-intro') == 'yes'
  if not enabled then
    return
  end
  local seg = effective_segments()['intro']
  if not seg then
    return
  end
  local pos = state.position
  if pos > seg['end'] - 1.5 then
    return
  end
  if pos < seg['start'] - 1 then
    return
  end
  seek_abs(seg['end'])
  toast('已跳过片头 · ' .. fmt_time(seg['end']), 3)
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
        mp.commandv('script-message', 'xnx-event',
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
      label = '片段标记（Alt+N）',
      value = current_segment() and '已有标记' or '无',
      kind = 'item',
      act = function()
        mark_segment()
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

local function open_menu(id)
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

function mark_dirty()
  dirty = true
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
  local thickness = hovered and 8 or BAR_H
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
        knob, knob, knob / 2, WHITE, 0x00
      )
    end

    -- Chapter ticks.
    for _, chapter in ipairs(state.chapters) do
      if chapter.time and chapter.time > 0 and chapter.time < duration then
        local cx = x + w * (chapter.time / duration)
        parts[#parts + 1] = rect(cx - 1, top - 5, 2, thickness + 10, 1, WHITE, 0x66)
      end
    end

    -- Intro / outro markers from chapters or manual marks.
    local segments = effective_segments()
    for _, seg in pairs(segments) do
      local s = math.max(0, math.min(duration, seg['start']))
      local e = math.max(0, math.min(duration, seg['end']))
      if e > s then
        local sx = x + w * (s / duration)
        local ex = x + w * (e / duration)
        parts[#parts + 1] = rect(sx, top + thickness + 2, math.max(2, ex - sx), 3, 1.5, WHITE, 0x40)
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
    parts[#parts + 1] = rect(px - bw / 2, top - 46, bw, 32, 8, BLACK, 0xA0)
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
  parts[#parts + 1] = rect(bx, 66, bw, 60, 30, BLACK, 0xA8)
  parts[#parts + 1] = text(W / 2, 81, 26, WHITE, alpha, clip(label, 46), 8, false)
end

local function draw_scrim(parts)
  local alphas = { 0x0C, 0x1C, 0x30, 0x48, 0x62, 0x7E, 0x9C, 0xBC }
  local y0 = 620
  local band = (H - y0) / #alphas
  for i, alpha in ipairs(alphas) do
    parts[#parts + 1] = rect(0, y0 + (i - 1) * band, W, band + 1, 0, BLACK, alpha)
  end
end

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
  parts[#parts + 1] = rect(px, py, pw, ph, 26, BLACK, 0xC8)
  parts[#parts + 1] = text(px + 28, py + 20, 20, DIM, 0x00, '统计信息 · I 关闭', 7, true)
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
    { 'Shift + ← →', '快退 / 快进 30 秒' },
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
    { 'F10 / F11', '音轨 / 字幕' },
    { 'Tab', '显示 / 隐藏界面' },
    { 'Esc', '关闭菜单 / 返回' },
    { '1 – 9', '跳转到 10% – 90%' },
  }
  local pw, ph = 1180, 120 + math.ceil(#lines / 2) * 44
  local px, py = (W - pw) / 2, (H - ph) / 2
  parts[#parts + 1] = rect(px, py, pw, ph, 30, BLACK, 0xE4)
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
  local budget = 560
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

  parts[#parts + 1] = rect(left, top, MENU_W, height, 26, BLACK, 0xC6)
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
        parts[#parts + 1] = rect(left + 12, y + 3, MENU_W - 24, ROW_H - 6, 14, WHITE, 0xFF)
      elseif hovered then
        parts[#parts + 1] = rect(left + 12, y + 3, MENU_W - 24, ROW_H - 6, 14, WHITE, 0x1E)
      end
      local fg = selected and BLACK or WHITE
      local dim = selected and '&H3A3A3A&' or DIM
      local label = clip(row.label or '', 34)
      if row.active and not selected then
        parts[#parts + 1] = rect(left + 24, y + ROW_H / 2 - 3, 6, 6, 3, WHITE, 0xFF)
      end
      local tx = left + 28
      if row.active and not selected then
        tx = left + 42
      end
      parts[#parts + 1] = text(tx, y + 12, 22, fg, 0x00, label, 7, row.active)
      local vx = left + MENU_W - 28
      if row.kind == 'adjust' then
        vx = vx - 46
      end
      if row.value then
        parts[#parts + 1] = text(vx, y + 13, 20, dim, 0x00, row.value, 9, false)
      end
      if row.kind == 'adjust' then
        parts[#parts + 1] = text(left + MENU_W - 28, y + 13, 16,
          selected and '&H6A6A6A&' or DIM, 0x00, '← →', 9, false)
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

local function draw_chrome(parts)
  local title = state.title ~= '' and state.title or state.fallback_title
  title = clip(title, 56)
  parts[#parts + 1] = text(SAFE, TITLE_Y, 40, WHITE, 0x00, title, 7, true)

  local badges = video_badges()
  if badges ~= '' then
    parts[#parts + 1] = text(SAFE, META_Y, 20, GREY, 0x00, badges, 7, false)
  end

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

function render()
  hits = {}

  if state.help then
    local parts = {}
    draw_help(parts)
    osd.data = table.concat(parts, '\\N')
    osd:update()
    return
  end

  if not state.visible then
    -- A toast still needs to be readable with the chrome hidden (volume, seek).
    if state.toast then
      local parts = {}
      draw_toast(parts)
      osd.data = table.concat(parts, '\\N')
      osd:update()
    else
      osd.data = ''
      osd:remove()
    end
    return
  end

  local parts = {}

  if state.audio_mode then
    -- No video: paint our own stage, but keep the transport bar usable.
    draw_audio_stage(parts)
  else
    draw_scrim(parts)
    draw_chrome(parts)
  end

  if state.stats then
    draw_stats(parts)
  end

  draw_progress(parts)
  draw_controls(parts)

  if state.menu then
    draw_menu(parts)
  end

  draw_toast(parts)

  osd.data = table.concat(parts, '\\N')
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
  mp.commandv('script-message', 'xnx-event', utils.format_json({ type = 'back', seq = seq }))
end

-- ==== INPUT ================================================================

local function handle_key(raw)
  local name, mods = esc_key_name(raw)
  local shift = has_mod(mods, 'shift')
  local alt = has_mod(mods, 'alt')

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
    mp.commandv('script-message', 'xnx-event', utils.format_json({ type = 'ui', seq = seq }))
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
    seek_rel(shift and -30 or -5)
  elseif name == 'right' then
    seek_rel(shift and 30 or 5)
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
      mark_segment()
    else
      command('playlist-next', 'force')
    end
  elseif name == 'o' and alt then
    -- Flutter owns the file dialog; the OSD cannot open one.
    seq = seq + 1
    mp.commandv('script-message', 'xnx-event', utils.format_json({ type = 'subtitle', seq = seq }))
  elseif name == 'b' and alt then
    command('playlist-prev')
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
  elseif name == 'f11' then
    open_menu('subtitle')
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
  { 'F10', 'f10' }, { 'F11', 'f11' },
  { 'Alt+n', 'alt+n' },
  { 'Alt+o', 'alt+o' },
  { '1', '1' }, { '2', '2' }, { '3', '3' }, { '4', '4' }, { '5', '5' },
  { '6', '6' }, { '7', '7' }, { '8', '8' }, { '9', '9' },
}

for _, entry in ipairs(BINDINGS) do
  local binding, name = entry[1], entry[2]
  -- Binding names must be unique: `i` and `I` share a handler but not an id.
  local id = entry[3] or name
  mp.add_key_binding(binding, 'xnx-' .. id:gsub('%+', '-'), function()
    handle_key(name)
  end)
end

mp.add_key_binding('MBTN_LEFT', 'xnx-click', function()
  local p = state.pointer
  if not p then
    return
  end
  local hit = hit_at(p.x, p.y)
  if hit and hit.onClick then
    hit.onClick()
  elseif state.menu then
    close_menu()
  elseif state.visible then
    toggle_ui()
  else
    show()
  end
end)

mp.add_key_binding('MBTN_RIGHT', 'xnx-context', function()
  if not close_menu() then
    if state.visible then
      open_menu('more')
    else
      show()
    end
  end
end)

mp.add_key_binding('WHEEL_UP', 'xnx-wheel-up', function()
  add_volume(5)
end)

mp.add_key_binding('WHEEL_DOWN', 'xnx-wheel-down', function()
  add_volume(-5)
end)

-- ==== MOUSE ================================================================

--- Maps window pixels into the 1920x1080 design space.
local function to_design(mx, my)
  local dim = mp.get_property_native('osd-dimensions')
  if dim and dim.w and dim.w > 0 and dim.h and dim.h > 0 then
    local ox = dim.ml or 0
    local oy = dim.mt or 0
    local scale = dim.w / W
    if scale > 0.0001 then
      return (mx - ox) / scale, (my - oy) / scale
    end
  end
  return mx, my
end

mp.observe_property('mouse-pos', 'native', function(_, value)
  if not value or not value.x then
    state.pointer = nil
    state.hover = nil
    return
  end
  if value.hover == false then
    state.pointer = nil
    state.hover = nil
    mark_dirty()
    return
  end
  local x, y = to_design(value.x, value.y)
  state.pointer = { x = x, y = y }
  local hit = hit_at(x, y)
  local id = hit and hit.id or nil
  if id ~= state.hover then
    state.hover = id
    mark_dirty()
  end
  if state.visible then
    schedule_hide()
  else
    -- Moving the mouse brings the chrome back, the way every desktop player
    -- does it. mouse-pos only fires on real movement.
    show()
  end
end)

-- ==== IPC ==================================================================

mp.register_script_message('xnx-cmd', function(json)
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
  elseif cmd == 'key' and payload.key then
    handle_key(payload.key)
  elseif cmd == 'title' then
    state.title = payload.title or ''
    mark_dirty()
  elseif cmd == 'toast' then
    toast(payload.text or '')
  elseif cmd == 'menu' and payload.id then
    open_menu(payload.id)
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
  -- Auto-skip the ending once we drift into it. Guarded so it fires at most
  -- once per file and never fights a deliberate rewind.
  if not outro_skipped and mp.get_property('user-data/xnx/skip-intro') == 'yes' then
    local seg = effective_segments()['outro']
    if seg and state.position > seg['start'] - 1.5 and state.position < seg['end'] - 1 then
      outro_skipped = true
      seek_abs(seg['end'])
      toast('已跳过片尾', 3)
    end
  end
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

mp.observe_property('user-data/xnx/title', 'string', function(_, value)
  state.title = value or ''
  mark_dirty()
end)

mp.observe_property('chapter-list', 'native', function(_, value)
  state.chapters = type(value) == 'table' and value or {}
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

mp.observe_property('aid', 'string', function()
  refresh_menu()
  mark_dirty()
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
  outro_skipped = false
  mark_dirty()
  render()
  schedule_hide()
  mp.add_timeout(0.8, function()
    maybe_skip(true)
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
