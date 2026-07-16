#!/bin/sh

# Ждём, пока X-сервер стартует
sleep 1

# Загружаем Xresources (цвета, шрифты и т.д.)
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources

# Установка обоев
feh --bg-fill ~/pictures/wallpapers.jpg &

# Настройка повтора клавиш
xset r rate 200 50 &

# Natural Scrolling
xinput set-prop 9 "libinput Natural Scrolling Enabled" 1

# Запуск композитора (прозрачность, тени)
picom --daemon &

# Запуск кастомной панели
bash ~/.config/chadwm/scripts/bar.sh &

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
