#!/bin/sh
# 4G 模块重启
#   modem-restart.sh            软复位：AT+CFUN=1,1（不断 USB 供电）
#   modem-restart.sh --hard     硬复位：USB authorized 0/1，强制重新枚举
#   modem-restart.sh --check    只打印环境，不做动作

DEV="$(uci -q get lpac.main.at_device || echo /dev/ttyUSB1)"
SEL="$(uci -q get ec200a.ec200a.sim_sel || echo 0)"
USBDEV="/sys/bus/usb/devices/1-1"

if [ "$1" = "--check" ]; then
	echo "dev=$DEV sim_sel=$SEL usb=$USBDEV authorized=$(cat $USBDEV/authorized 2>/dev/null || echo n/a)"
	exit 0
fi

wait_dev() {
	i=0
	while [ $i -lt 30 ]; do
		sleep 2
		i=$((i + 1))
		[ -e "$DEV" ] && return 0
	done
	return 1
}

restore() {
	[ -x /usr/libexec/wt6285/sim.sh ] && /usr/libexec/wt6285/sim.sh "$SEL" >/dev/null 2>&1
	ifup wan >/dev/null 2>&1
}

case "$1" in
--hard)
	logger -t wt6285 "modem restart: hard (usb re-enumerate)"
	if [ -w "$USBDEV/authorized" ]; then
		# 先掉电再上电，间隔 3 秒；中途异常也要恢复
		trap 'echo 1 > "$USBDEV/authorized" 2>/dev/null' EXIT INT TERM
		echo 0 > "$USBDEV/authorized"
		sleep 3
		echo 1 > "$USBDEV/authorized"
		trap - EXIT INT TERM
	else
		# 退化到 unbind/bind
		echo -n "1-1" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null
		sleep 3
		echo -n "1-1" > /sys/bus/usb/drivers/usb/bind 2>/dev/null
	fi
	;;
*)
	logger -t wt6285 "modem restart: soft (AT+CFUN=1,1)"
	/usr/bin/sms_tool -d "$DEV" at "AT+CFUN=1,1" >/dev/null 2>&1
	;;
esac

if wait_dev; then
	restore
	logger -t wt6285 "modem restart: done"
else
	logger -t wt6285 "modem restart: device did not reappear, skip restore"
fi

exit 0
