--[[===========================================================================
iTechniqs — Conky config for Graham Adams
Hardware : Dell laptop, Intel i5-7200U (2 cores / 4 threads)
Display  : 1920x1080 HD, 100% font scaling
Sensors  : hwmon4 = coretemp | hwmon3 = dell_smm (fan)
Network  : eth0 (wired) / wlp1s0 (wireless) — auto-detects active
Battery  : No battery — silently suppressed via lua helper (auto-enables on install)
Font     : Ubuntu family throughout (Regular, Bold, Light, Condensed)

Ring y-anchor positions (must match seamod_rings.lua exactly):
  CPU    y=70
  MEM    y=280
  STORE  y=480
  DISKIO y=600
  NET    y=720

voffset calibration — Ubuntu:size=10 line height ~ 17px
  To fine-tune alignment: adjust the 4 gap voffsets marked with TUNE THIS.
  Decrease if label is still too low, increase if too high.
  Change in 2px steps and killall conky && conky -c ... to preview.

CUSTOMISATION NOTES:
  - Fan sensor: ${hwmon 3 fan 1} — Dell SMM fan1
  - CPU temps:  hwmon 4 temp 1=Package, temp 2=Core0, temp 3=Core1
  - Network:    replace eth0/wlp1s0 if your interface names differ
                Run: ip link show | grep -v lo
  - Disk IO:    sda assumed. Run: lsblk -d -o NAME,TYPE | grep disk
  - Partitions: /home, /, /var — if no separate /var, change arg to /boot or /
===========================================================================--]]

conky.config = {

    background          = true,
    update_interval     = 1,

    cpu_avg_samples     = 2,
    net_avg_samples     = 2,
    temperature_unit    = 'celsius',
    if_up_strictness    = 'address',

    double_buffer       = true,
    no_buffers          = true,
    text_buffer_size    = 2048,

    own_window          = true,
    own_window_class    = 'conky-seamod',
    own_window_type     = 'desktop',
    own_window_colour   = '#000000',
    own_window_transparent  = true,
    own_window_argb_visual  = true,
    own_window_argb_value   = 60,

    draw_shades         = false,
    draw_outline        = false,
    draw_borders        = false,
    draw_graph_borders  = false,

    alignment           = 'top_right',
    gap_x               = 10,
    gap_y               = 35,
    minimum_width       = 355,
    minimum_height      = 500,
    maximum_width       = 395,
    border_inner_margin = 0,
    border_outer_margin = 10,

    override_utf8_locale = true,
    use_xft             = true,
    font                = 'Ubuntu:size=10',
    xftalpha            = 0.8,
    uppercase           = false,

    top_cpu_separate    = true,
    top_name_verbose    = true,
    top_name_width      = 22,
    short_units         = true,

    default_color       = '#FFFFFF',
    color1              = '#DDDDDD',
    color2              = '#AAAAAA',
    color3              = '#888888',
    color4              = '#555555',
    color5              = '#EF5A29',
    color6              = '#2D6A92',
    color7              = '#77B753',
    color8              = '#FF5C2B',
    color9              = '#E8C040',

    lua_load            = '~/.conky/seamod/seamod_rings.lua',
    lua_draw_hook_post  = 'main',
};

conky.text = [[
# ══════════════════════════════════════════
#  CPU  (rings at y=70 — text starts at window top, no leading voffset)
# ══════════════════════════════════════════
${offset 210}${color1}${font Ubuntu:style=Bold:size=10}Temp:${font Ubuntu:size=10} ${alignr}${color4}[${hwmon 4 temp 2},${hwmon 4 temp 3}]  ${color2}${hwmon 4 temp 1} °C
${offset 210}${color1}${font Ubuntu:style=Bold:size=10}Fan:${font Ubuntu:size=10}  ${alignr}${color2}${hwmon 3 fan 1} RPM
${offset 210}${color1}${font Ubuntu:style=Bold:size=10}Freq:${font Ubuntu:size=10} ${alignr}${color4}[${lua freq_min}-${lua freq_max}]  ${color2}${lua freq_avg} MHz
${offset 145}${cpugraph cpu0 45,0 606060 909090}
${voffset -45}${goto 95}${font Ubuntu:style=Bold:size=12}${color6}   PROC
${offset 85}${font Ubuntu:size=11}${color5}${top name 1}${alignr}${top cpu 1}%
${offset 85}${font Ubuntu:size=10}${color1}${top name 2}${alignr}${top cpu 2}%
${offset 85}${font Ubuntu:size=9}${color2}${top name 3}${alignr}${top cpu 3}%
${offset 85}${font Ubuntu:style=Light:size=9}${color3}${top name 4}${alignr}${top cpu 4}%
${offset 85}${font Ubuntu:style=Light:size=9}${color4}${top name 5}${alignr}${top cpu 5}%
${voffset 8}\
# ══════════════════════════════════════════
#  MEM  (rings at y=280)
#  TUNE THIS voffset if MEM label is too high or low ↑
# ══════════════════════════════════════════
${offset 230}${color1}${font Ubuntu:style=Bold:size=10}Available: ${alignr}${font Ubuntu:size=10}${color2}${memeasyfree}
${offset 230}${color1}${font Ubuntu:style=Bold:size=10}Cache:     ${alignr}${font Ubuntu:size=10}${color2}${cached}
${offset 230}${color1}${font Ubuntu:style=Bold:size=10}Buffer:    ${alignr}${font Ubuntu:size=10}${color2}${buffers}
${offset 145}${memgraph 45,0 606060 909090}
${voffset -40}${goto 95}${font Ubuntu:style=Bold:size=12}${color6}    MEM
${offset 85}${font Ubuntu:size=11}${color5}${top_mem name 1}${alignr}${top_mem mem_res 1}
${offset 85}${font Ubuntu:size=10}${color1}${top_mem name 2}${alignr}${top_mem mem_res 2}
${offset 85}${font Ubuntu:size=9}${color2}${top_mem name 3}${alignr}${top_mem mem_res 3}
${offset 85}${font Ubuntu:style=Light:size=9}${color3}${top_mem name 4}${alignr}${top_mem mem_res 4}
${offset 85}${font Ubuntu:style=Light:size=9}${color4}${top_mem name 5}${alignr}${top_mem mem_res 5}
${voffset 8}\
# ══════════════════════════════════════════
#  STORE  (rings at y=480)
#  TUNE THIS voffset if STORE label is too high or low ↑
# ══════════════════════════════════════════
${offset 230}${color1}${font Ubuntu:style=Bold:size=10}Read:  ${alignr}${font Ubuntu:size=10}${color2}${diskio_read}
${offset 230}${color1}${font Ubuntu:style=Bold:size=10}Write: ${alignr}${font Ubuntu:size=10}${color2}${diskio_write}
${offset 230}${color1}${font Ubuntu:size=10} 
${offset 145}${diskiograph 45,0 606060 909090}
${voffset -40}${goto 95}${font Ubuntu:style=Bold:size=12}${color6}  STORE
${offset 85}${font Ubuntu:size=11}${color5}${top_io name 1}${alignr}${font Ubuntu:size=10}${color7}r:${top_io io_read 1} ${color8}w:${top_io io_write 1}
${offset 85}${font Ubuntu:size=10}${color1}${top_io name 2}${alignr}${font Ubuntu:size=9}${color7}r:${top_io io_read 2} ${color8}w:${top_io io_write 2}
${offset 85}${font Ubuntu:size=9}${color2}${top_io name 3}${alignr}${font Ubuntu:size=9}${color7}r:${top_io io_read 3} ${color8}w:${top_io io_write 3}
${offset 85}${font Ubuntu:style=Light:size=9}${color3}${top_io name 4}${alignr}${font Ubuntu:size=9}${color7}r:${top_io io_read 4} ${color8}w:${top_io io_write 4}
${offset 85}${font Ubuntu:style=Light:size=9}${color4}${top_io name 5}${alignr}${font Ubuntu:size=9}${color7}r:${top_io io_read 5} ${color8}w:${top_io io_write 5}
${voffset 8}\
# ══════════════════════════════════════════
#  DISK IO  (rings at y=600)
#  TUNE THIS voffset if DISK IO label is too high or low ↑
# ══════════════════════════════════════════
${offset 230}${color7}${font Ubuntu:style=Bold:size=10}sda Read:  ${alignr}${font Ubuntu:size=10}${diskio_read sda}
${offset 230}${color8}${font Ubuntu:style=Bold:size=10}sda Write: ${alignr}${font Ubuntu:size=10}${diskio_write sda}
${offset 230}${color1}${font Ubuntu:size=10} 
${offset 145}${diskiograph sda 22,0 324D23 77B753 -l}
${offset 145}${diskiograph sda 22,0 4B1B0C FF5C2B -l}
${voffset -70}${goto 95}${font Ubuntu:style=Bold:size=12}${color6}DISK IO
${voffset 28}\
${voffset 8}\
# ══════════════════════════════════════════
#  NET  (rings at y=720)
#  TUNE THIS voffset if NET label is too high or low ↑
# ══════════════════════════════════════════
${if_match "${addr eth0}" != "No Address"}\
${offset 180}${color1}${font Ubuntu:style=Bold:size=10}Wired
${offset 180}${color1}${font Ubuntu:style=Bold:size=10}IP:        ${alignr}${font Ubuntu:size=10}${color2}${addr eth0}
${offset 180}${color1}${font Ubuntu:style=Bold:size=10}Public IP: ${alignr}${font Ubuntu:size=10}${color2}${curl http://api.ipify.org 300}
${offset 145}${upspeedgraph eth0 30,0 4B1B0C FF5C2B 10240KiB -l}
${offset 225}${color1}${font Ubuntu:size=10}Up: ${alignr}${color3}${upspeed eth0} / ${totalup eth0}
${offset 145}${downspeedgraph eth0 30,0 324D23 77B753 10240KiB -l}
${offset 225}${color1}${font Ubuntu:size=10}Down: ${alignr}${color3}${downspeed eth0} / ${totaldown eth0}
${else}\
${if_match "${addr wlp1s0}" != "No Address"}\
${offset 180}${color1}${font Ubuntu:style=Bold:size=10}WiFi: ${alignr}${font Ubuntu:size=10}${color2}${wireless_essid wlp1s0} (${wireless_bitrate wlp1s0})
${offset 180}${color1}${font Ubuntu:style=Bold:size=10}IP:        ${alignr}${font Ubuntu:size=10}${color2}${addr wlp1s0}
${offset 180}${color1}${font Ubuntu:style=Bold:size=10}Public IP: ${alignr}${font Ubuntu:size=10}${color2}${curl http://api.ipify.org 300}
${offset 145}${upspeedgraph wlp1s0 30,0 4B1B0C FF5C2B 10240KiB -l}
${offset 225}${color1}${font Ubuntu:style=Bold:size=10}Up: ${alignr}${color3}${upspeed wlp1s0} / ${totalup wlp1s0}
${offset 145}${downspeedgraph wlp1s0 30,0 324D23 77B753 10240KiB -l}
${offset 225}${color1}${font Ubuntu:style=Bold:size=10}Down: ${alignr}${color3}${downspeed wlp1s0} / ${totaldown wlp1s0}
${else}\
${offset 145}${color3}${font Ubuntu:style=Bold:size=10}Disconnected
${offset 145}${font Ubuntu:size=9}${color4}(eth0 and wlp1s0 have no IP)
${offset 145}${upspeedgraph eth0 30,0 4B1B0C FF5C2B 10240KiB -l}
${offset 145}${downspeedgraph eth0 30,0 324D23 77B753 10240KiB -l}
${endif}\
${endif}\
${voffset -85}${goto 95}${font Ubuntu:style=Bold:size=12}${color6}       NET
${voffset 105}\
# ══════════════════════════════════════════
#  EXTRA INFO — add freely below, ring alignment is done
# ══════════════════════════════════════════
${color4}${hr 1}
${offset 10}${color1}${font Ubuntu:style=Bold:size=10}Uptime:  ${alignr}${color3}${font Ubuntu:size=10}$uptime
${offset 10}${color1}${font Ubuntu:style=Bold:size=10}Host:    ${alignr}${color3}${font Ubuntu:size=10}$nodename
${offset 10}${color1}${font Ubuntu:style=Bold:size=10}Kernel:  ${alignr}${color3}${font Ubuntu:size=10}$kernel
${lua_parse battery_block}\
${color4}${hr 1}
${offset 10}${color9}${font Ubuntu:style=Bold:size=10}SECURITY
${offset 10}${font Ubuntu:size=9}${color3}Alerts (24h): ${alignr}${color9}${texecpi 60 grep -c "$(date '+%Y-%m-%d')" /var/log/itechniqs-alerts.log 2>/dev/null || echo 0}
${offset 10}${font Ubuntu:size=9}${color3}Last event:
${offset 10}${font Ubuntu Condensed:style=Light:size=8}${color3}${texecpi 30 tail -1 /var/log/itechniqs-alerts.log 2>/dev/null | sed 's/\[.*\] \[/[/g' | cut -c1-55 || echo "none"}
${color4}${hr 1}
${offset 10}${color6}${font Ubuntu:style=Bold:size=10}JOURNAL ${font Ubuntu:size=9}${color1}(errors/warnings):
${voffset 3}${color3}${font Ubuntu Condensed:style=Light:size=8}${texecpi 15 ~/.conky/seamod/journal-err-feed.sh 2>/dev/null || echo "journal feed unavailable"}
]];
