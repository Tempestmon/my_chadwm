#!/bin/sh
# Screen locker: i3lock-color in the Ultraviolet palette.
#
# Called by xss-lock (idle timeout, `loginctl lock-session`, before sleep),
# never directly from key bindings, so every lock goes through one path.
# --nofork keeps i3lock in the foreground: xss-lock then knows exactly when
# the screen is locked/unlocked (needed for --transfer-sleep-lock).
set -eu

script_dir=$(dirname "$(readlink -f "$0")")
# Palette vars: black grey darkblue white blue green red (generated)
. "$script_dir/bar_themes/ultraviolet"

# i3lock-color wants RRGGBBAA without '#'
c() { printf '%sff' "${1#\#}"; }

font=Iosevka

exec i3lock --nofork \
    --ignore-empty-password --show-failed-attempts \
    --color="$(c "$black")" \
    --indicator --radius=120 --ring-width=8 \
    --inside-color="$(c "$grey")" --ring-color="$(c "$blue")" \
    --line-uses-inside --separator-color=00000000 \
    --keyhl-color="$(c "$green")" --bshl-color="$(c "$red")" \
    --insidever-color="$(c "$grey")" --ringver-color="$(c "$green")" \
    --insidewrong-color="$(c "$grey")" --ringwrong-color="$(c "$red")" \
    --clock --time-str="%H:%M" --date-str="%a %d %b" \
    --time-color="$(c "$white")" --date-color="$(c "$darkblue")" \
    --time-font="$font" --date-font="$font" --verif-font="$font" --wrong-font="$font" \
    --time-size=48 --date-size=18 \
    --verif-text="checking…" --wrong-text="wrong" --noinput-text="empty" \
    --verif-color="$(c "$green")" --wrong-color="$(c "$red")" \
    --keylayout 1 --layout-color="$(c "$darkblue")" --layout-font="$font"
