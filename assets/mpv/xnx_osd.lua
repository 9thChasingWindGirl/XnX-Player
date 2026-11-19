--[[
  XnX Player — in-player OSD
  ---------------------------------------------------------------------------
  mpv renders the video into a native child window that always sits above the
  Flutter canvas, so the whole in-player UI has to live inside mpv. This script
  draws it as an ASS overlay in a fixed 1920x1080 coordinate space.

  Design: PlayStation 5 system UI. A dark stage, monochrome chrome, hairline
  progress, no blue. Everything is drawn with plain ASS vector commands so the
  only dependency is mpv itself.

  Sections: CONST / ASS / STATE / LAYOUT / RENDER / INPUT / IPC / LIFECYCLE
--]]

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

-- ==== CONST ================================================================

local W, H = 1920, 1080
local SAFE = 96
local BAR_X = SAFE
local BAR_W = W - SAFE * 2
local BAR_Y = 966
local BAR_H = 4
local TITLE_Y = 836
local META_Y = 890
local TIME_Y = 982
local AUTOHIDE = 5.0
local TICK = 0.1

local WHITE = '&HFFFFFF&'
local GREY = '&H9A9A9A&'
local BLACK = '&H000000&'

-- ==== ASS ==================================================================

local function escape_text(s)
  if s == nil then
    return ''
  end
  s = tostring(s)
  s = s:gsub('[{}]', '')
  s = s:gsub('[\r\n]+', ' ')
  return s
end

local function rounded_path(w, h, r)
  r = math.min(r, w / 2, h / 2)
  if r <= 0.5 then
    return 'm 0 0 l ' .. w .. ' 0 ' .. w .. ' ' .. h .. ' 0 ' .. h
  end
  local d = r * 0.4477
  return table.concat({
    'm ' .. r .. ' 0',
    'l ' .. (w - r) .. ' 0',
    'b ' .. (w - d) .. ' 0 ' .. w .. ' ' .. (r - d) .. ' ' .. w .. ' ' .. r,
    'l ' .. w .. ' ' .. (h - r),
    'b ' .. w .. ' ' .. (h - r + d) .. ' ' .. (w - r + d) .. ' ' .. h .. ' ' .. (w - r) .. ' ' .. h,
    'l ' .. r .. ' ' .. h,
    'b ' .. (r - d) .. ' ' .. h .. ' 0 ' .. (h - r + d) .. ' 0 ' .. (h - r),
    'l 0 ' .. r,
    'b 0 ' .. (r - d) .. ' ' .. (r - d) .. ' 0 ' .. r .. ' 0',
  }, ' ')
end

local function fill(x, y, w, h, r, color, alpha)
  x = math.floor(x)
  y = math.floor(y)
  return string.format(
    '{\\an7\\pos(%d,%d)\\p1\\bord0\\shad0\\1c%s\\1a&H%02X&}%s{\\p0}',
    x, y, color, alpha, rounded_path(w, h, r)
  )
end

local function label(x, y, size, color, alpha, str, align)
  x = math.floor(x)
  y = math.floor(y)
  return string.format(
    '{\\an%d\\pos(%d,%d)\\fs%d\\bord0\\shad0\\c%s\\1a&H%02X&}%s',
    align or 7, x, y, size, color, alpha, escape_text(str)
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

-- ==== STATE ================================================================

local osd = mp.create_osd_overlay('ass-events')
osd.res_x = W
osd.res_y = H
osd.z = 1000

local state = {
  visible = false,
  paused = false,
  title = '',
  fallback_title = '',
  position = 0,
  duration = 0,
  cache = 0,
}

local dirty = true
local hide_timer = nil
local seq = 0

-- ==== RENDER ===============================================================

local function render()
  if not state.visible then
    osd.data = ''
    osd:remove()
    return
  end

  local parts = {}

  -- Bottom scrim: five bands standing in for a gradient (ASS has none).
  local alphas = { 0xE8, 0xD2, 0xB4, 0x92, 0x70 }
  for i = 1, #alphas do
    parts[#parts + 1] = fill(0, 700 + (i - 1) * 76, W, 76, 0, BLACK, alphas[i])
  end

  local progress = 0
  if state.duration > 0 then
    progress = math.max(0, math.min(1, state.position / state.duration))
  end

  local title = state.title
  if title == nil or title == '' then
    title = state.fallback_title
  end
  if #title > 52 then
    title = title:sub(1, 52) .. '…'
  end

  parts[#parts + 1] = label(BAR_X, TITLE_Y, 38, WHITE, 0x00, title)
  parts[#parts + 1] = label(BAR_X, META_Y, 24, GREY, 0x50, fmt_time(state.position) .. ' / ' .. fmt_time(state.duration))

  -- Track
  parts[#parts + 1] = fill(BAR_X, BAR_Y, BAR_W, BAR_H, BAR_H / 2, WHITE, 0x40)
  if state.cache > 0 and state.duration > 0 then
    local cache_w = math.floor(BAR_W * math.min(1, state.cache / state.duration))
    if cache_w > 2 then
      parts[#parts + 1] = fill(BAR_X, BAR_Y, cache_w, BAR_H, BAR_H / 2, WHITE, 0x18)
    end
  end
  local played_w = math.floor(BAR_W * progress)
  if played_w > 2 then
    parts[#parts + 1] = fill(BAR_X, BAR_Y, played_w, BAR_H, BAR_H / 2, WHITE, 0x00)
  end

  -- Playhead: a soft dot sitting on the hairline.
  local knob_x = BAR_X + played_w - 6
  parts[#parts + 1] = fill(knob_x, BAR_Y - 4, 12, 12, 6, WHITE, 0x00)

  -- Times
  parts[#parts + 1] = label(BAR_X, TIME_Y, 22, GREY, 0x40, fmt_time(state.position))
  parts[#parts + 1] = label(BAR_X + BAR_W, TIME_Y, 22, GREY, 0x40, fmt_time(state.duration), 9)

  -- Pause badge, kept on screen while paused (the bar never auto-hides then).
  if state.paused then
    local cx, cy = W / 2, H / 2
    parts[#parts + 1] = fill(cx - 44, cy - 44, 88, 88, 44, BLACK, 0x60)
    parts[#parts + 1] = fill(cx - 20, cy - 24, 10, 48, 3, WHITE, 0x00)
    parts[#parts + 1] = fill(cx + 10, cy - 24, 10, 48, 3, WHITE, 0x00)
    parts[#parts + 1] = label(cx, cy + 68, 24, WHITE, 0x30, '已暂停', 5)
  end

  osd.data = table.concat(parts, '\\N')
  osd:update()
end

local function mark_dirty()
  dirty = true
end

local function set_visible(visible)
  state.visible = visible
  mark_dirty()
  render()
end

local function schedule_hide()
  if hide_timer ~= nil then
    hide_timer:kill()
    hide_timer = nil
  end
  if state.paused then
    return
  end
  hide_timer = mp.add_timeout(AUTOHIDE, function()
    hide_timer = nil
    set_visible(false)
  end)
end

local function show()
  set_visible(true)
  schedule_hide()
end

local function toggle()
  if state.visible then
    if hide_timer ~= nil then
      hide_timer:kill()
      hide_timer = nil
    end
    set_visible(false)
  else
    show()
  end
end

-- ==== INPUT ================================================================

local function send(payload)
  seq = seq + 1
  payload.seq = seq
  mp.commandv('script-message', 'xnx-event', utils.format_json(payload))
end

mp.add_key_binding('MBTN_LEFT', 'xnx-toggle', function()
  toggle()
end)

mp.add_key_binding('MBTN_RIGHT', 'xnx-back', function()
  send({ type = 'back' })
end)

mp.add_key_binding('ESC', 'xnx-escape', function()
  send({ type = 'back' })
end)

-- ==== IPC ==================================================================

mp.register_script_message('xnx-cmd', function(json)
  local ok, payload = pcall(utils.parse_json, json)
  if not ok or type(payload) ~= 'table' then
    msg.debug('bad command: ' .. tostring(json))
    return
  end
  if payload.cmd == 'show' then
    show()
  elseif payload.cmd == 'hide' then
    set_visible(false)
  elseif payload.cmd == 'title' then
    state.title = payload.title or ''
    mark_dirty()
  end
end)

-- ==== LIFECYCLE ============================================================

mp.observe_property('time-pos', 'number', function(_, value)
  state.position = value or 0
  mark_dirty()
end)

mp.observe_property('duration', 'number', function(_, value)
  state.duration = value or 0
  mark_dirty()
end)

mp.observe_property('demuxer-cache-time', 'number', function(_, value)
  state.cache = value or 0
  mark_dirty()
end)

mp.observe_property('media-title', 'string', function(_, value)
  state.fallback_title = value or ''
  mark_dirty()
end)

mp.observe_property('user-data/xnx/title', 'string', function(_, value)
  state.title = value or ''
  mark_dirty()
end)

mp.observe_property('pause', 'bool', function(_, value)
  state.paused = value == true
  if state.paused then
    if hide_timer ~= nil then
      hide_timer:kill()
      hide_timer = nil
    end
    set_visible(true)
  else
    mark_dirty()
    schedule_hide()
  end
end)

mp.observe_property('osd-dimensions', 'native', function()
  mark_dirty()
  render()
end)

mp.register_event('file-loaded', function()
  show()
end)

mp.add_periodic_timer(TICK, function()
  if dirty and state.visible then
    dirty = false
    render()
  end
end)

render()
