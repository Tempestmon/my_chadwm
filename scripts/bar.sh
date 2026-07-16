#!/bin/dash

# ^c$var^ = fg color
# ^b$var^ = bg color

interval=0

# load colors
. ~/.config/chadwm/scripts/bar_themes/rosepine

cpu() {
  cpu_val=$(grep -o "^[^ ]*" /proc/loadavg)

  printf "^c$green^ "
  printf "^c$green^ $cpu_val"
}

pkg_updates() {
  updates=$({ timeout 20 apt list --upgradable 2>/dev/null || true; } | grep -c upgradable)
  if [ "$updates" -eq 0 ]; then
    printf "  ^c$green^    Fully Updated"
  else
    printf "  ^c$green^    $updates updates"
  fi
}

battery() {
  get_capacity="$(cat /sys/class/power_supply/BAT0/capacity)"
  online=$(cat /sys/class/power_supply/AC/online)
  if [ "$online" -eq 1 ]; then
	printf "^c$green^ 󰂄 $get_capacity %s%%"
  else
	if [ "$get_capacity" -le 10 ]; then
		printf "^c$red^ 󰂃 $get_capacity %s%%"
	else
		printf "^c$blue^ 󰁹 $get_capacity %s%%"
	fi
  fi
}

brightness() {
  printf "^c$white^ 󰛨"
  printf "^c$white^%.0f%s%%\n" $(light -G)
}

mem() {
  printf "^c$blue^  "
  printf "^c$blue^ $(free -m | awk '/^Mem/ { print $3 }' | sed s/i//g)MiB"
}

wlan() {
	case "$(cat /sys/class/net/wl*/operstate 2>/dev/null)" in
	up) printf "^c$blue^ 󰤨 ^d^%s" " ^c$blue^Connected" ;;
	down) printf "^c$blue^ 󰤭 ^d^%s" " ^c$blue^Disconnected" ;;
	esac
}

clock() {
	printf "^c$darkblue^  󱑆 "
	printf "^c$blue^ $(date '+%d.%m.%y %H:%M:%S')  "
}

cpu_temp() {
	temp=$(sensors coretemp-isa-0000 -j | jq '."coretemp-isa-0000"."Package id 0".temp1_input')
	temp_rounded=$(printf "%.0f" $temp)
	printf "^c$green^ "
	printf "^c$green^ $temp_rounded°C"
}

gpu_usage() {
	usage=$(nvidia-smi --query-gpu utilization.gpu --format=csv,noheader)
	printf "^c$black^ ^b$red^GPU"
	printf "^c$white^ ^b$grey^ $usage%"
}

gpu_mem() {
	mem=$(nvidia-smi --query-gpu memory.used --format=csv,noheader)
	printf "^c$black^ ^b$red^ "
	printf "^c$white^ ^b$grey^ $mem"
}

gpu_temp() {
	temp=$(nvidia-smi --query-gpu temperature.gpu --format=csv,noheader)
	printf "^c$black^ ^b$red^"
	printf "^c$white^ ^b$grey^ $temp°C"
}

vpn_status() {
	status=$(if pidof openvpn > /dev/null; then echo "true"; else echo "false"; fi)
	case "$status" in (true) printf "^c$green^ ^b$black^󰱔" ;;
	(false) printf "^c$red^ ^b$black^󰱟" ;;
	esac
}

dwm_alsa () {
    STATUS=$(amixer sget Master | tail -n1 | sed -r "s/.*\[(.*)\]/\1/")
    VOL=$(amixer get Master | tail -n1 | sed -r "s/.*\[(.*)%\].*/\1/")
    printf "%s" "$SEP1"
    if [ "$STATUS" = "off" ]; then
	    printf "^c$red^ "
    else
	#removed this line becuase it may get confusing
	if [ "$VOL" -gt 0 ] && [ "$VOL" -le 33 ]; then
	    printf "^c$green^  %s%%" "$VOL"
	elif [ "$VOL" -gt 33 ] && [ "$VOL" -le 66 ]; then
	    printf "^c$green^  %s%%" "$VOL"
	else
	    printf "^c$green^  %s%%" "$VOL"
	fi
    fi
    printf "%s\n" "$SEP2"
}

while true; do
  [ $interval = 0 ] || [ $(($interval % 7200)) = 0 ] && updates=$(pkg_updates)
  interval=$((interval + 1))
  sleep 0.5 && xsetroot -name "$(dwm_alsa) $(brightness) $(battery) $(wlan) $(cpu) $(cpu_temp) $(mem) $updates $(clock)"
done
