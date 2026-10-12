#!/bin/sh

# Ждём, пока X-сервер стартует
sleep 1

# Resolve sibling scripts relative to this file, so the repo can live anywhere
script_dir=$(dirname "$(readlink -f "$0")")

# X resources (Xft rendering, DPI) live in the repo next to this script
xrdb -merge "$script_dir/../.Xresources"

# Display: the monitor's preferred mode is 4K@60; force 240 Hz over DP (DSC).
# On failure we just stay at 60 Hz instead of breaking the session.
xrandr --output DP-0 --mode 3840x2160 --rate 240 || true

# --- Audio -------------------------------------------------------------
# PipeWire spawns WirePlumber and pipewire-pulse itself
# (see /etc/pipewire/pipewire.conf.d). It is not an X client, so it would
# outlive the session; kill leftovers on start and stop it on exit.
stop_audio() {
    pkill -u "$(id -u)" -x 'pipewire|wireplumber'
}
stop_audio
trap stop_audio EXIT
trap 'exit 0' INT TERM HUP

pipewire >"$XDG_RUNTIME_DIR/pipewire.log" 2>&1 &

# Установка обоев
feh --bg-fill ~/pictures/wallpapers.jpg &

# Настройка повтора клавиш
xset r rate 200 50 &

# Natural Scrolling
xinput set-prop 9 "libinput Natural Scrolling Enabled" 1

# Compositor: explicit config from the repo; log to tmpfs for debugging.
picom --config "$script_dir/../picom/picom.conf" --daemon \
    --log-file "$XDG_RUNTIME_DIR/picom.log" --log-level warn

# Screen lock: blank/lock after 10 min idle, monitor off after 15 min;
# xss-lock also locks on `loginctl lock-session` and before suspend.
xset s 600 600
xset dpms 900 900 900
xss-lock --transfer-sleep-lock -- "$script_dir/lock.sh" &

# Запуск кастомной панели
bash "$script_dir/bar.sh" &

# Language layout
setxkbmap -layout "us,ru" -option "grp:win_space_toggle"

# Clipboard history on disk so it survives reboots (default is tmpfs $XDG_RUNTIME_DIR).
# Exported: clipmenu/clipdel launched later from chadwm keybinds and terminals
# must use the same cache. Note: the disk is unencrypted; keep the history short
# and never record password manager windows.
export CM_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/clipmenu"
export CM_SELECTIONS=clipboard # explicit copies only, not every mouse selection
export CM_MAX_CLIPS=200
export CM_IGNORE_WINDOW='KeePassXC' # regex on window title
mkdir -p -m 700 "$CM_DIR"
clipmenud &

# Notifications
dunst &

# eww
eww open activate-linux

# Основной цикл: перезапуск chadwm
while type chadwm >/dev/null; do chadwm && continue || break; done
