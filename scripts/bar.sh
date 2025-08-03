#!/bin/dash

# ^c$var^ = fg color
# ^b$var^ = bg color

interval=0

# load colors
. ~/.config/chadwm/scripts/bar_themes/onedark

cpu() {
  cpu_val=$(grep -o "^[^ ]*" /proc/loadavg)

  printf "^c$black^ ^b$green^ "
  printf "^c$white^ ^b$grey^ $cpu_val"
}

pkg_updates() {
  #updates=$({ timeout 20 doas xbps-install -un 2>/dev/null || true; } | wc -l) # void
  updates=$({ timeout 20 checkupdates 2>/dev/null || true; } | wc -l) # arch
  # updates=$({ timeout 20 aptitude search '~U' 2>/dev/null || true; } | wc -l)  # apt (ubuntu, debian etc)

  if [ -z "$updates" ]; then
    printf "  ^c$green^    Fully Updated"
  else
    printf "  ^c$green^    $updates"" updates"
  fi
}

battery() {
  get_capacity="$(cat /sys/class/power_supply/BAT1/capacity)"
  printf "^c$blue^   $get_capacity"
}

brightness() {
  printf "^c$red^   "
  printf "^c$red^%.0f\n" $(cat /sys/class/backlight/*/brightness)
}

mem() {
  printf "^c$blue^^b$black^  "
  printf "^c$blue^ $(free -m | awk '/^Mem/ { print $3 }' | sed s/i//g)MiB"
}

wlan() {
	case "$(cat /sys/class/net/wl*/operstate 2>/dev/null)" in
	up) printf "^c$black^ ^b$blue^ 󰤨 ^d^%s" " ^c$blue^Connected" ;;
	down) printf "^c$black^ ^b$blue^ 󰤭 ^d^%s" " ^c$blue^Disconnected" ;;
	esac
}

clock() {
	printf "^c$black^ ^b$darkblue^ 󱑆 "
	printf "^c$black^^b$blue^ $(date '+%H:%M:%S')  "
}

cpu_temp() {
	temp=$(sensors k10temp-pci-00c3 -j | jq '."k10temp-pci-00c3".Tccd1.temp3_input')
	temp_rounded=$(printf "%.0f" $temp)
	printf "^c$black^ ^b$green^ "
	printf "^c$white^ ^b$grey^ $temp_rounded°C"
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

while true; do

  [ $interval = 0 ] || [ $(($interval % 3600)) = 0 ] && updates=$(pkg_updates)
  interval=$((interval + 1))

  sleep 1 && xsetroot -name "$(vpn_status) $(gpu_usage) $(gpu_mem) $(gpu_temp) $(cpu) $(cpu_temp) $(mem) $(clock)"
done
