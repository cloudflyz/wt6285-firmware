#!/bin/sh
# sim.sh 0|1|2   0=外置 1=内置1 2=内置2
sel="$1"
case "$sel" in 0|1|2) ;; *) echo "用法: sim.sh 0|1|2" >&2; exit 2 ;; esac

set_gpio() {
	[ -e "/sys/class/gpio/$1" ] || echo "$2" > /sys/class/gpio/export 2>/dev/null
	echo "$3" > "/sys/class/gpio/$1/value" 2>/dev/null
}

case "$sel" in
	0) set_gpio cpe-sel0 40 1; set_gpio cpe-sel1 44 0 ;;
	1) set_gpio cpe-sel0 40 0; set_gpio cpe-sel1 44 1 ;;
	2) set_gpio cpe-sel0 40 0; set_gpio cpe-sel1 44 0 ;;
esac

uci set ec200a.ec200a.sim_sel="$sel"
uci commit ec200a
echo "$sel" > /tmp/Sim_Sel

DEV="$(uci -q get lpac.main.at_device || echo /dev/ttyUSB1)"
/usr/bin/sms_tool -d "$DEV" at 'AT+CFUN=1,1' >/dev/null 2>&1
echo "OK $sel"
