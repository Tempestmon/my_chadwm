#!/bin/sh

# Ждём, пока X-сервер стартует
sleep 1

# Resolve sibling scripts relative to this file, so the repo can live anywhere
script_dir=$(dirname "$(readlink -f "$0")") 

# X resources (Xft rendering, DPI) live in the repo next to this script
xrdb -merge "$script_dir/../.Xresources"

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

# Запуск композитора (прозрачность, тени)
picom --daemon &

# Запуск кастомной панели
bash "$script_dir/bar.sh" &

# Language layout
setxkbmap -layout "us,ru" -option "grp:win_space_toggle"

# Clipboard
clipmenud &

# Notifications
dunst &

# eww
eww open activate-linux

# Основной цикл: перезапуск chadwm
while type chadwm >/dev/null; do chadwm && continue || break; done
