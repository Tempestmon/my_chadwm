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
# Colors: black green white grey blue red darkblue
. "$script_dir/bar_themes/rosepine"

# Icons are Nerd Fonts v3 glyphs. If one gets lost when copying, re-insert it
# in Vim (insert mode): Ctrl+v, then U and the 8-digit code, e.g. U000F057E.
ICON_VOL_HIGH='󰕾'  # U+F057E nf-md-volume_high
ICON_VOL_MED='󰖀'  # U+F0580 nf-md-volume_medium
ICON_VOL_LOW='󰕿'  # U+F057F nf-md-volume_low
ICON_VOL_MUTE='󰖁'  # U+F0581 nf-md-volume_off
ICON_CPU=''  # U+F4BC nf-oct-cpu
ICON_TEMP='󰔏'  # U+F050F nf-md-thermometer
ICON_GPU='󰢮'  # U+F08AE nf-md-expansion_card
ICON_MEM='󰍛'  # U+F035B nf-md-memory
ICON_PKG='󰏖'  # U+F03D6 nf-md-package_variant
ICON_CLOCK='󱑆'  # U+F1446 nf-md-clock_time_eight
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

cpu_load() {
    read -r load _ < /proc/loadavg || return 0
    printf '^c%s^%s %s' "$green" "$ICON_CPU" "$load"
}

cpu_temp() {
    [ -n "$cpu_hwmon" ] || return 0
    # temp1 on k10temp is Tctl, in millidegrees Celsius
    millideg=$(cat "$cpu_hwmon/temp1_input" 2>/dev/null) || return 0
    printf '^c%s^%s %s°C' "$green" "$ICON_TEMP" "$((millideg / 1000))"
}

gpu() {
    # One nvidia-smi call for both values: "45, 3"
    out=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu \
        --format=csv,noheader,nounits 2>/dev/null) || return 0
    temp=${out%%,*}
    util=${out##*, }
    printf '^c%s^%s %s°C %s%%' "$red" "$ICON_GPU" "$temp" "$util"
}

memory() {
    # Used = MemTotal - MemAvailable (what free(1) calls "used" plus reclaimable)
    used=$(awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 }
        END { if (t) printf "%.1f", (t - a) / 1048576 }' /proc/meminfo)
    [ -n "$used" ] || return 0
    printf '^c%s^%s %sG' "$blue" "$ICON_MEM" "$used"
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
    for block in "$(vpn)" "$(volume)" "$(cpu_load)" "$(cpu_temp)" "$gpu_cache" \
        "$(memory)" "$(updates)" "$(clock)"; do
        [ -n "$block" ] && line="$line  $block"
    done
    printf '%s  ' "$line"
}

gpu_cache=$(gpu)

if [ "${1:-}" = "--once" ]; then
    status_line
    echo
    exit 0
fi

tick=0
while :; do
    # nvidia-smi is relatively expensive, refresh it every 5 s
    [ $((tick % 5)) -eq 0 ] && gpu_cache=$(gpu)
    [ $((tick % 3600)) -eq 0 ] && refresh_updates
    [ $((tick % 30)) -eq 0 ] && refresh_egress

    # When the X server is gone, xsetroot fails: exit instead of
    # lingering after the session ends.
    xsetroot -name "$(status_line)" 2>/dev/null || exit 0

    tick=$((tick + 1))
    sleep 1
done
