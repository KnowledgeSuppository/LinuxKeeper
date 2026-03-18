--[[===========================================================================
iTechniqs — Seamod Rings for Graham Adams
Hardware : Intel i5-7200U (2 cores / 4 threads)
Display  : 1920x1080 HD, 100% scaling
Author   : SeaJey → JPvRiel → iTechniqs customisation
Version  : v1.0 (2026-03-17)

Ring layout (y anchor positions, all x=70):
  CPU     y=55   — 4 threads, radii 60→39 (step 7, thickness 5)
  MEM     y=280  — RAM outer (r=60,t=10) + SWAP inner (r=45,t=10)
  STORE   y=480  — /home (r=60,t=8), / (r=48,t=8), /var (r=36,t=8)
  DISKIO  y=600  — sda read (r=55,t=7), sda write (r=44,t=7)
  NET     y=720  — Down (r=60,t=8), Up (r=48,t=8), WiFi signal (r=30,t=8)
===========================================================================--]]

require 'cairo'

-- ── Battery helper (used in conkyrc.lua via ${lua battery_status}) ────────────
-- Silently returns '' if no battery present. Avoids stderr spam.
function conky_battery_status()
    local f = io.open('/sys/class/power_supply/BAT0/status', 'r')
    if f then
        local s = f:read('*l'); f:close()
        local pf = io.open('/sys/class/power_supply/BAT0/capacity', 'r')
        if pf then
            local p = pf:read('*l'); pf:close()
            return p .. '% (' .. s .. ')'
        end
        return s
    end
    -- No battery — check for BAT1 as well
    local f1 = io.open('/sys/class/power_supply/BAT1/status', 'r')
    if f1 then
        local s = f1:read('*l'); f1:close()
        local pf1 = io.open('/sys/class/power_supply/BAT1/capacity', 'r')
        if pf1 then
            local p = pf1:read('*l'); pf1:close()
            return p .. '% (' .. s .. ')'
        end
        return s
    end
    return ''  -- no battery — silent, no warnings
end

function conky_battery_bar()
    local f = io.open('/sys/class/power_supply/BAT0/capacity', 'r')
    if f then
        local p = tonumber(f:read('*l')); f:close()
        return p or 0
    end
    return -1  -- sentinel: caller draws nothing
end

-- Called via ${lua_parse battery_block} in conkyrc.lua
-- Returns a fully formatted conky text line when battery present,
-- empty string when absent — zero stderr, zero warnings.
function conky_battery_block()
    local status = conky_battery_status()
    if status == nil or status == '' then
        return ''
    end
    return '${offset 10}${color1}${font Roboto:medium:size=10}Battery:  ${alignr}${color3}${font Roboto:regular:size=10}' .. status .. '\n'
end

-- ── CPU frequency helpers ─────────────────────────────────────────────────────
function conky_nproc()
    return io.popen('nproc'):read('*n')
end

nproc = conky_nproc()

function cpu_freq_list()
    local fl = {}
    for i = 1, nproc do
        fl[i] = tonumber(conky_parse('${freq ' .. i .. '}')) or 0
    end
    return fl
end

function conky_freq_min()
    return math.min(table.unpack(cpu_freq_list()))
end

function conky_freq_max()
    return math.max(table.unpack(cpu_freq_list()))
end

function conky_freq_avg()
    local fl = cpu_freq_list()
    local sum = 0
    for i = 1, #fl do sum = sum + fl[i] end
    return math.floor((sum / #fl) + 0.5)
end

-- ── Gauge table ───────────────────────────────────────────────────────────────
gauge = {

-- ═══════════════════════════════════════════════════════
--  CPU  (4 threads — i5-7200U: cpu1,cpu2 = core0 HTs
--                              cpu3,cpu4 = core1 HTs)
--  Paired by physical core for visual clarity:
--    cpu1+cpu2 share outer pair  (r=60, r=53)
--    cpu3+cpu4 share inner pair  (r=46, r=39)
-- ═══════════════════════════════════════════════════════
{
    name='cpu',             arg='cpu1',         max_value=100,
    x=65,                   y=65,
    graph_radius=60,        graph_thickness=5,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=0,
    txt_weight=0,           txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=28,
    graduation_thickness=0, graduation_mark_thickness=1,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.3,
},
{
    name='cpu',             arg='cpu2',         max_value=100,
    x=65,                   y=65,
    graph_radius=53,        graph_thickness=5,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=0,
    txt_weight=0,           txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=28,
    graduation_thickness=0, graduation_mark_thickness=1,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.3,
},
{
    name='cpu',             arg='cpu3',         max_value=100,
    x=65,                   y=65,
    graph_radius=44,        graph_thickness=5,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=0,
    txt_weight=0,           txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=28,
    graduation_thickness=0, graduation_mark_thickness=1,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.3,
},
{
    name='cpu',             arg='cpu4',         max_value=100,
    x=65,                   y=65,
    graph_radius=37,        graph_thickness=5,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=0,
    txt_weight=0,           txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=28,
    graduation_thickness=0, graduation_mark_thickness=1,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.3,
},

-- ═══════════════════════════════════════════════════════
--  MEMORY  (y=280)
--  RAM outer ring (r=60, thick=10)
--  SWAP inner ring (r=45, thick=10)
-- ═══════════════════════════════════════════════════════
{
    name='memperc',         arg='',             max_value=100,
    x=65,                   y=240,
    graph_radius=60,        graph_thickness=10,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=72,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=54,
    graduation_thickness=0, graduation_mark_thickness=2,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.5,
    caption='RAM',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},
{
    name='swapperc',        arg='',             max_value=100,
    x=65,                   y=240,
    graph_radius=45,        graph_thickness=10,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=33,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=23,
    graduation_thickness=0, graduation_mark_thickness=2,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.5,
    caption='SWAP',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},

-- ═══════════════════════════════════════════════════════
--  STORAGE — filesystem usage  (y=480)
--  Adjust partitions to match your actual layout.
--  To check: df -h --output=target,pcent | grep -v tmpfs
-- ═══════════════════════════════════════════════════════
{
    name='fs_used_perc',    arg='/home',        max_value=100,
    x=65,                   y=420,
    graph_radius=60,        graph_thickness=8,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=70,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=23,
    graduation_thickness=0, graduation_mark_thickness=2,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='home',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},
{
    name='fs_used_perc',    arg='/',            max_value=100,
    x=65,                   y=420,
    graph_radius=48,        graph_thickness=8,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=58,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=23,
    graduation_thickness=0, graduation_mark_thickness=2,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='root',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},
{
    -- Change '/var' to another partition if you don't have a separate /var
    -- e.g. arg='/data' or arg='/mnt/backup'
    -- If only / and /home exist, set this to '/' and reduce graph_radius to 36
    name='fs_used_perc',    arg='/var',         max_value=100,
    x=65,                   y=420,
    graph_radius=36,        graph_thickness=8,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=26,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=30,
    graduation_thickness=0, graduation_mark_thickness=2,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='var',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},

-- ═══════════════════════════════════════════════════════
--  DISK I/O — per disk read/write rings  (y=600)
--  sda: outer=read, inner=write
--  max_value=100 = 100 MB/s (adjust if your disk is faster)
--  To find your disk name: lsblk -d -o NAME,TYPE | grep disk
-- ═══════════════════════════════════════════════════════
{
    name='diskio_read',     arg='sda',          max_value=100,
    x=65,                   y=580,
    graph_radius=55,        graph_thickness=7,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0x77B753,  hand_fg_alpha=1.0,  -- green for read
    txt_radius=65,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0x77B753, txt_fg_alpha=1.0,
    graduation_radius=20,
    graduation_thickness=0, graduation_mark_thickness=2,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='Read',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},
{
    name='diskio_write',    arg='sda',          max_value=100,
    x=65,                   y=580,
    graph_radius=44,        graph_thickness=7,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xFF5C2B,  hand_fg_alpha=1.0,  -- orange for write
    txt_radius=54,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0xFF5C2B, txt_fg_alpha=1.0,
    graduation_radius=20,
    graduation_thickness=0, graduation_mark_thickness=2,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='Write',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},

-- ═══════════════════════════════════════════════════════
--  NETWORK  (y=720)
--  Detects wired (eth0/enp*) or wireless (wlan0/wlp*) automatically
--  conky_line handles the conditional — falls back to 0 if disconnected
--  Down outer (r=60), Up inner (r=48), WiFi signal innermost (r=30)
-- ═══════════════════════════════════════════════════════
{
    conky_line='${if_match "${addr eth0}" != "No Address"}${downspeedf eth0}${else}${if_match "${addr wlp1s0}" != "No Address"}${downspeedf wlp1s0}${else}0${endif}${endif}',
    name='downspeedf',      arg='eth0',         max_value=100,
    x=65,                   y=720,
    graph_radius=60,        graph_thickness=8,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=70,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=68,
    graduation_thickness=0, graduation_mark_thickness=2,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='Down',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},
{
    conky_line='${if_match "${addr eth0}" != "No Address"}${upspeedf eth0}${else}${if_match "${addr wlp1s0}" != "No Address"}${upspeedf wlp1s0}${else}0${endif}${endif}',
    name='upspeedf',        arg='eth0',         max_value=100,
    x=65,                   y=720,
    graph_radius=48,        graph_thickness=8,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=58,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=56,
    graduation_thickness=0, graduation_mark_thickness=2,
    graduation_unit_angle=27,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='Up',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},
{
    conky_line='${if_match "${addr wlp1s0}" != "No Address"}${wireless_link_qual_perc wlp1s0}${else}0${endif}',
    name='wireless_link_qual_perc', arg='wlp1s0', max_value=100,
    x=65,                   y=720,
    graph_radius=30,        graph_thickness=8,
    graph_start_angle=180,
    graph_unit_angle=2.7,   graph_unit_thickness=2.7,
    graph_bg_colour=0xffffff, graph_bg_alpha=0.1,
    graph_fg_colour=0xFFFFFF, graph_fg_alpha=0.3,
    hand_fg_colour=0xEF5A29,  hand_fg_alpha=1.0,
    txt_radius=20,
    txt_weight=1.0,         txt_size=8.0,
    txt_fg_colour=0xEF5A29, txt_fg_alpha=1.0,
    graduation_radius=38,
    graduation_thickness=3, graduation_mark_thickness=2,
    graduation_unit_angle=14,
    graduation_fg_colour=0xFFFFFF, graduation_fg_alpha=0.3,
    caption='Signal',
    caption_weight=0.8,     caption_size=9.0,
    caption_fg_colour=0xFFFFFF, caption_fg_alpha=0.5,
},

}   -- end gauge table

-- ── Cairo drawing engine (unchanged from original) ────────────────────────────

function rgb_to_r_g_b(colour, alpha)
    return ((colour / 0x10000) % 0x100) / 255.,
           ((colour / 0x100)   % 0x100) / 255.,
           (colour % 0x100)             / 255.,
           alpha
end

function angle_to_position(start_angle, current_angle)
    local pos = current_angle + start_angle
    return ((pos * (2 * math.pi / 360)) - (math.pi / 2))
end

function draw_gauge_ring(display, data, value, border)
    local max_value = data['max_value']
    local x, y = data['x'] + border, data['y'] + border
    local graph_radius = data['graph_radius']
    local graph_thickness, graph_unit_thickness = data['graph_thickness'], data['graph_unit_thickness']
    local graph_start_angle = data['graph_start_angle']
    local graph_unit_angle  = data['graph_unit_angle']
    local graph_bg_colour,  graph_bg_alpha  = data['graph_bg_colour'],  data['graph_bg_alpha']
    local graph_fg_colour,  graph_fg_alpha  = data['graph_fg_colour'],  data['graph_fg_alpha']
    local hand_fg_colour,   hand_fg_alpha   = data['hand_fg_colour'],   data['hand_fg_alpha']
    local graph_end_angle = (max_value * graph_unit_angle) % 360

    -- background ring
    cairo_arc(display, x, y, graph_radius,
        angle_to_position(graph_start_angle, 0),
        angle_to_position(graph_start_angle, graph_end_angle))
    cairo_set_source_rgba(display, rgb_to_r_g_b(graph_bg_colour, graph_bg_alpha))
    cairo_set_line_width(display, graph_thickness)
    cairo_stroke(display)

    -- value arc (segmented)
    local val = value % (max_value + 1)
    local start_arc, stop_arc = 0, 0
    local i = 1
    while i <= val do
        start_arc = (graph_unit_angle * i) - graph_unit_thickness
        stop_arc  = (graph_unit_angle * i)
        cairo_arc(display, x, y, graph_radius,
            angle_to_position(graph_start_angle, start_arc),
            angle_to_position(graph_start_angle, stop_arc))
        cairo_set_source_rgba(display, rgb_to_r_g_b(graph_fg_colour, graph_fg_alpha))
        cairo_stroke(display)
        i = i + 1
    end
    local angle = start_arc

    -- hand (current value marker)
    start_arc = (graph_unit_angle * val) - graph_unit_thickness
    stop_arc  = (graph_unit_angle * val)
    cairo_arc(display, x, y, graph_radius,
        angle_to_position(graph_start_angle, start_arc),
        angle_to_position(graph_start_angle, stop_arc))
    cairo_set_source_rgba(display, rgb_to_r_g_b(hand_fg_colour, hand_fg_alpha))
    cairo_stroke(display)

    -- graduation marks
    local graduation_radius         = data['graduation_radius']
    local graduation_thickness      = data['graduation_thickness']
    local graduation_mark_thickness = data['graduation_mark_thickness']
    local graduation_unit_angle     = data['graduation_unit_angle']
    local graduation_fg_colour      = data['graduation_fg_colour']
    local graduation_fg_alpha       = data['graduation_fg_alpha']
    if graduation_radius > 0 and graduation_thickness > 0 and graduation_unit_angle > 0 then
        local nb = graph_end_angle / graduation_unit_angle
        local j = 0
        while j < nb do
            cairo_set_line_width(display, graduation_thickness)
            start_arc = (graduation_unit_angle * j) - (graduation_mark_thickness / 2)
            stop_arc  = (graduation_unit_angle * j) + (graduation_mark_thickness / 2)
            cairo_arc(display, x, y, graduation_radius,
                angle_to_position(graph_start_angle, start_arc),
                angle_to_position(graph_start_angle, stop_arc))
            cairo_set_source_rgba(display, rgb_to_r_g_b(graduation_fg_colour, graduation_fg_alpha))
            cairo_stroke(display)
            cairo_set_line_width(display, graph_thickness)
            j = j + 1
        end
    end

    -- value text
    local txt_radius = data['txt_radius']
    local txt_weight, txt_size = data['txt_weight'], data['txt_size']
    local txt_fg_colour, txt_fg_alpha = data['txt_fg_colour'], data['txt_fg_alpha']
    if txt_radius > 0 then
        local movex = txt_radius * math.cos(angle_to_position(graph_start_angle, angle))
        local movey = txt_radius * math.sin(angle_to_position(graph_start_angle, angle))
        cairo_select_font_face(display, "ubuntu", CAIRO_FONT_SLANT_NORMAL, txt_weight)
        cairo_set_source_rgba(display, rgb_to_r_g_b(txt_fg_colour, txt_fg_alpha))
        cairo_set_font_size(display, txt_size)
        cairo_move_to(display, x + movex - (txt_size / 2), y + movey + 3)
        cairo_show_text(display, value)
        cairo_stroke(display)
    end

    -- caption label
    local caption = data['caption']
    local caption_weight, caption_size = data['caption_weight'], data['caption_size']
    local caption_fg_colour, caption_fg_alpha = data['caption_fg_colour'], data['caption_fg_alpha']
    local tox = graph_radius * (math.cos((graph_start_angle * 2 * math.pi / 360) - (math.pi / 2)))
    local toy = graph_radius * (math.sin((graph_start_angle * 2 * math.pi / 360) - (math.pi / 2)))
    cairo_select_font_face(display, "ubuntu", CAIRO_FONT_SLANT_NORMAL, caption_weight)
    cairo_set_font_size(display, caption_size)
    cairo_set_source_rgba(display, rgb_to_r_g_b(caption_fg_colour, caption_fg_alpha))
    cairo_move_to(display, x + tox + 5, y + toy + 5)
    if graph_start_angle < 105 then
        cairo_move_to(display, x + tox - 30, y + toy + 1)
    end
    cairo_show_text(display, caption)
    cairo_stroke(display)
end

function go_gauge_rings(display, border)
    local function load_gauge_rings(display, data)
        local str = ''
        if data['conky_line'] == nil then
            str = string.format('${%s %s}', data['name'], data['arg'])
        else
            str = data['conky_line']
        end
        str = conky_parse(str)
        local value = tonumber(str)
        if value == nil then value = 0 else value = math.floor(value + 0.5) end
        draw_gauge_ring(display, data, value, border)
    end
    for i in pairs(gauge) do
        load_gauge_rings(display, gauge[i])
    end
end

function conky_main()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual, conky_window.width, conky_window.height)
    local display = cairo_create(cs)
    go_gauge_rings(display, conky_window.border_outer_margin)
    cairo_surface_destroy(cs)
    cairo_destroy(display)
end
