#!/bin/sh
# Status bar for chadwm on the Void desktop (Ryzen + NVIDIA, wired, no battery).
#
# Prints a status2d-formatted line into the root window name via xsetroot.
# Error handling: every block degrades gracefully - on failure it prints
# nothing, so one broken data source never blanks the whole bar.
#
# Usage:
#   bar.sh          run the loop (started from run.sh)
#   bar.sh --once   print one status line to stdout and exit (for testing)

set -u

script_dir=$(dirname "$(readlink -f "$0")")
# Colors (generated from theme/palette.env): black green white grey blue red darkblue
. "$script_dir/bar_themes/ultraviolet"

# Icons are Nerd Fonts v3 glyphs. If one gets lost when copying, re-insert it
# in Vim (insert mode): Ctrl+v, then U and the 8-digit code, e.g. U000F057E.
ICON_VOL_HIGH='󰕾'  # U+F057E nf-md-volume_high
ICON_VOL_MED='󰖀'  # U+F0580 nf-md-volume_medium
ICON_VOL_LOW='󰕿'  # U+F057F nf-md-volume_low
ICON_VOL_MUTE='󰖁'  # U+F0581 nf-md-volume_off
ICON_LOAD='󰊚'  # U+F029A nf-md-gauge (load average)
ICON_TEMP='󰔏'  # U+F050F nf-md-thermometer
ICON_GPU='󰢮'  # U+F08AE nf-md-expansion_card
ICON_MEM='󰍛'  # U+F035B nf-md-memory
ICON_DISK='󰋊'  # U+F02CA nf-md-harddisk
ICON_NET='󰈀'  # U+F0200 nf-md-ethernet
ICON_DOWN='󰁅'  # U+F0045 nf-md-arrow_down
ICON_UP='󰁝'  # U+F005D nf-md-arrow_up
ICON_PKG='󰏖'  # U+F03D6 nf-md-package_variant
ICON_CLOCK='󱑆'  # U+F1446 nf-md-clock_time_eight
ICON_DND='󰂛'  # U+F009B nf-md-bell_off
ICON_KBD='󰌌'  # U+F030C nf-md-keyboard
ICON_VPN_OK='󰕥'  # U+F0565 nf-md-shield_check
ICON_VPN_WARN='󰻌'  # U+F0ECC nf-md-shield_alert
ICON_VPN_OFF='󰦞'  # U+F099E nf-md-shield_off

# Where slow blocks cache their output between ticks.
cache_dir=${XDG_RUNTIME_DIR:-/tmp}/chadwm-bar
mkdir -p "$cache_dir"

# hwmon indexes (hwmon0, hwmon1, ...) are not stable across boots,
# so look the sensor up by its driver name once at startup.
find_hwmon() {
    for dir in /sys/class/hwmon/hwmon*; do
        if [ "$(cat "$dir/name" 2>/dev/null)" = "$1" ]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}
cpu_hwmon=$(find_hwmon k10temp || true)

# Personal VPN: Xray (SOCKS inbound) + tun2socks (TUN device -> SOCKS).
# Override the interface name if your tun2socks uses a different one.
vpn_iface=${BAR_VPN_IFACE:-tun0}
sys_net=${BAR_SYS_NET:-/sys/class/net}   # overridable for tests
proc_dir=${BAR_PROC:-/proc}              # overridable for tests

# --- blocks -----------------------------------------------------------------

volume() {
    # Output: "Volume: 0.45" or "Volume: 0.45 [MUTED]"
    out=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || return 0
    case $out in
        *MUTED*)
            printf '^c%s^%s muted' "$red" "$ICON_VOL_MUTE"
            return 0
            ;;
    esac
    pct=$(echo "$out" | awk '{ printf "%d", $2 * 100 + 0.5 }')
    if [ "$pct" -le 33 ]; then
        icon=$ICON_VOL_LOW
    elif [ "$pct" -le 66 ]; then
        icon=$ICON_VOL_MED
    else
        icon=$ICON_VOL_HIGH
    fi
    printf '^c%s^%s %s%%' "$green" "$icon" "$pct"
}

vpn() {
    # Healthy only if all three links of the chain are alive:
    #   TUN interface up -> tun2socks process -> xray process.
    # tun2socks without xray is the dangerous case: traffic is routed into
    # the tunnel and blackholed, so it gets a distinct warning state.
    # (sv status needs root, so we check processes and the interface instead.)
    iface_up=0
    if flags=$(cat "$sys_net/$vpn_iface/flags" 2>/dev/null); then
        iface_up=$((flags & 1))   # IFF_UP
    fi
    t2s=0; pgrep -x tun2socks > /dev/null && t2s=1
    xray=0; pgrep -x xray > /dev/null && xray=1

    if [ "$t2s" -eq 1 ] && [ "$xray" -eq 1 ] && [ "$iface_up" -eq 1 ]; then
        # Tunnel is up; where does traffic actually exit? (see refresh_egress)
        loc=$(cat "$cache_dir/egress" 2>/dev/null || true)
        if [ "$loc" = "RU" ]; then
            # VPS unreachable: xray fell back to "direct"
            printf '^c%s^%s fallback' "$red" "$ICON_VPN_WARN"
        else
            printf '^c%s^%s VPN' "$green" "$ICON_VPN_OK"
        fi
    elif [ "$t2s" -eq 0 ] && [ "$iface_up" -eq 0 ]; then
        printf '^c%s^%s direct' "$white" "$ICON_VPN_OFF"
    else
        # Partial state: name what is missing
        missing=""
        [ "$iface_up" -eq 1 ] || missing="$missing $vpn_iface"
        [ "$t2s" -eq 1 ] || missing="$missing tun2socks"
        [ "$xray" -eq 1 ] || missing="$missing xray"
        printf '^c%s^%s down:%s' "$red" "$ICON_VPN_WARN" "$missing"
    fi
}

layout() {
    # Written by init_layout / the xkb-switch watcher; "us", "ru", "ru(phonetic)"...
    l=$(cat "$cache_dir/layout" 2>/dev/null) || return 0
    case $l in
        us*) printf '^c%s^%s EN' "$white" "$ICON_KBD" ;;
        ru*) printf '^c%s^%s RU' "$blue" "$ICON_KBD" ;;   # non-default layout stands out
        ?*)  printf '^c%s^%s %s' "$blue" "$ICON_KBD" "$(printf '%.2s' "$l" | tr '[:lower:]' '[:upper:]')" ;;
    esac
}

init_layout() {
    command -v xkb-switch > /dev/null || return 0
    xkb-switch -p > "$cache_dir/layout" 2>/dev/null || true
}

start_layout_watcher() {
    # Event-driven: `xkb-switch -W` prints the new layout on every switch.
    # We store it and poke the main loop with SIGUSR1 so the bar updates
    # immediately instead of on the next 1 s tick.
    command -v xkb-switch > /dev/null || return 0
    (
        xkb-switch -W 2>/dev/null | while read -r l; do
            printf '%s' "$l" > "$cache_dir/layout.tmp"
            mv "$cache_dir/layout.tmp" "$cache_dir/layout"
            kill -USR1 "$bar_pid" 2>/dev/null || exit 0
        done
    ) &
    watcher_pid=$!
}

dnd() {
    # Shown only while dunst is paused ("do not disturb"), with the number of
    # notifications waiting to be shown once it's turned off.
    [ "$(dunstctl is-paused 2>/dev/null)" = "true" ] || return 0
    waiting=$(dunstctl count waiting 2>/dev/null || echo 0)
    if [ "${waiting:-0}" -gt 0 ] 2>/dev/null; then
        printf '^c%s^%s DND %s' "$red" "$ICON_DND" "$waiting"
    else
        printf '^c%s^%s DND' "$red" "$ICON_DND"
    fi
}

cpu_load() {
    read -r load _ < "$proc_dir/loadavg" || return 0
    printf '^c%s^%s %s' "$green" "$ICON_LOAD" "$load"
}

cpu_temp() {
    [ -n "$cpu_hwmon" ] || return 0
    # temp1 on k10temp is Tctl, in millidegrees Celsius
    millideg=$(cat "$cpu_hwmon/temp1_input" 2>/dev/null) || return 0
    printf '^c%s^%s %s°C' "$green" "$ICON_TEMP" "$((millideg / 1000))"
}

gpu() {
    # One nvidia-smi call: "45, 3, 1234, 16376" (temp C, util %, VRAM used/total MiB)
    out=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total \
        --format=csv,noheader,nounits 2>/dev/null) || return 0
    echo "$out" | awk -F', *' -v c="$red" -v i="$ICON_GPU" 'NR == 1 {
        printf "^c%s^%s %s°C %s%% %.1f/%.0fG", c, i, $1, $2, $3 / 1024, $4 / 1024 }'
}

memory() {
    # Used = MemTotal - MemAvailable, i.e. memory that can't be reclaimed now
    awk -v c="$blue" -v i="$ICON_MEM" '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 }
        END { if (t) printf "^c%s^%s %.1f/%.0fG", c, i, (t - a) / 1048576, t / 1048576 }' \
        "$proc_dir/meminfo"
}

disk_usage() {
    # Root filesystem, used/size in GiB (df -P: 1K blocks, stable columns)
    df -P / 2>/dev/null | awk 'NR == 2 { printf "%.0f/%.0fG", $3 / 1048576, $2 / 1048576 }'
}

default_iface() {
    # Physical NIC of the main table's default route (not tun0)
    ip -o route show table main default 2>/dev/null | awk '{
        for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
}

human_rate() {
    # bytes/s -> fixed-width "  12K", " 3.4M", "  0B"; integer math only (dash)
    b=$1
    if [ "$b" -ge 1048576 ]; then
        t=$((b * 10 / 1048576)); printf '%4s' "$((t / 10)).$((t % 10))M"
    elif [ "$b" -ge 1024 ]; then
        printf '%4s' "$((b / 1024))K"
    else
        printf '%4s' "${b}B"
    fi
}

uptime_cs() {
    # /proc/uptime "12345.67 ..." -> 1234567 (centiseconds), for precise deltas
    read -r up _ < "$proc_dir/uptime"
    echo "${up%.*}${up#*.}"
}

disk_sectors() {
    # Sectors read + written, whole disks only (nvme0n1, sda), not partitions
    awk '$3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|vd[a-z]+)$/ { r += $6; w += $10 }
        END { print r + 0, w + 0 }' "$proc_dir/diskstats"
}

update_rates() {
    # Runs in the main shell (not in $(...)) so the previous sample survives.
    # Sets disk_io_cache and net_cache; the first call only primes counters.
    now=$(uptime_cs)
    # shellcheck disable=SC2046  # intentional split into two numbers
    set -- $(disk_sectors)
    d_r=$1 d_w=$2
    n_rx=0 n_tx=0
    if [ -n "$net_iface" ]; then
        read -r n_rx < "$sys_net/$net_iface/statistics/rx_bytes" 2>/dev/null || n_rx=0
        read -r n_tx < "$sys_net/$net_iface/statistics/tx_bytes" 2>/dev/null || n_tx=0
    fi
    if [ -n "${prev_t:-}" ] && [ "$now" -gt "$prev_t" ]; then
        dt=$((now - prev_t))   # centiseconds
        rd=$(( (d_r - prev_dr) * 512 * 100 / dt ))
        wr=$(( (d_w - prev_dw) * 512 * 100 / dt ))
        rx=$(( (n_rx - prev_rx) * 100 / dt ))
        tx=$(( (n_tx - prev_tx) * 100 / dt ))
        disk_io_cache="R$(human_rate "$rd") W$(human_rate "$wr")"
        if [ -n "$net_iface" ]; then
            net_cache=$(printf '^c%s^%s %s%s %s%s' "$green" "$ICON_NET" \
                "$ICON_DOWN" "$(human_rate "$rx")" "$ICON_UP" "$(human_rate "$tx")")
        fi
    fi
    prev_t=$now prev_dr=$d_r prev_dw=$d_w prev_rx=$n_rx prev_tx=$n_tx
}

disk() {
    [ -n "$disk_usage_cache" ] || return 0
    printf '^c%s^%s %s %s' "$blue" "$ICON_DISK" "$disk_usage_cache" "$disk_io_cache"
}

refresh_egress() {
    # Ask Cloudflare where our traffic exits (loc=XX). Through the tunnel this
    # is the VPS country; "RU" means xray's balancer fell back to "direct".
    # Background + atomic write, like refresh_updates.
    (
        trace=$(curl -s -m 8 https://1.1.1.1/cdn-cgi/trace 2>/dev/null) || exit 0
        loc=$(printf '%s\n' "$trace" | sed -n 's/^loc=//p')
        [ -n "$loc" ] || exit 0
        printf '%s' "$loc" > "$cache_dir/egress.tmp"
        mv "$cache_dir/egress.tmp" "$cache_dir/egress"
    ) &
}

refresh_updates() {
    # -M: fetch repodata into memory only, so no root is needed.
    # Runs in the background and writes atomically: a slow mirror never
    # stalls the bar, and a failed check keeps the previous value.
    (
        list=$(timeout 60 xbps-install -Mun 2>/dev/null) || exit 0
        printf '%s' "$list" | grep -c . > "$cache_dir/updates.tmp"
        mv "$cache_dir/updates.tmp" "$cache_dir/updates"
    ) &
}

updates() {
    count=$(cat "$cache_dir/updates" 2>/dev/null) || return 0
    [ "$count" -gt 0 ] 2>/dev/null || return 0
    printf '^c%s^%s %s' "$blue" "$ICON_PKG" "$count"
}

clock() {
    printf '^c%s^%s ^c%s^%s' "$darkblue" "$ICON_CLOCK" "$blue" "$(date '+%d.%m.%y %H:%M:%S')"
}

# --- main -------------------------------------------------------------------

status_line() {
    # Empty blocks are dropped, so there are no double spaces in the bar.
    line=""
    for block in "$(dnd)" "$(vpn)" "$(layout)" "$(volume)" "$(cpu_load)" "$(cpu_temp)" "$gpu_cache" \
        "$(memory)" "$(disk)" "$net_cache" "$(updates)" "$(clock)"; do
        [ -n "$block" ] && line="$line  $block"
    done
    printf '%s  ' "$line"
}

gpu_cache=$(gpu)
init_layout
disk_usage_cache=$(disk_usage)
disk_io_cache=""
net_cache=""
net_iface=${BAR_NET_IFACE:-$(default_iface)}
update_rates   # prime counters

if [ "${1:-}" = "--once" ]; then
    sleep 1; update_rates   # rates need two samples
    status_line
    echo
    exit 0
fi

bar_pid=$$
watcher_pid=
# USR1 = "something changed, redraw now" (interrupts the sleep below)
trap ':' USR1
# Turn termination signals into a normal exit so the EXIT trap (watcher
# cleanup) runs; dash skips EXIT traps on untrapped signals.
trap 'exit 0' TERM INT HUP
trap '[ -n "$watcher_pid" ] && { pkill -P "$watcher_pid"; kill "$watcher_pid"; } 2>/dev/null' EXIT
start_layout_watcher

tick=0
while :; do
    # nvidia-smi is relatively expensive, refresh it every 5 s
    [ $((tick % 5)) -eq 0 ] && gpu_cache=$(gpu)
    [ $((tick % 3600)) -eq 0 ] && refresh_updates
    [ $((tick % 30)) -eq 0 ] && refresh_egress
    if [ $((tick % 60)) -eq 0 ]; then
        disk_usage_cache=$(disk_usage)
        [ -n "${BAR_NET_IFACE:-}" ] || net_iface=$(default_iface)
    fi
    update_rates

    # When the X server is gone, xsetroot fails: exit instead of
    # lingering after the session ends.
    xsetroot -name "$(status_line)" 2>/dev/null || exit 0

    tick=$((tick + 1))
    # `wait` (unlike a foreground sleep) returns as soon as a trapped signal
    # arrives, so a layout switch redraws the bar instantly.
    sleep 1 &
    wait $!
done
