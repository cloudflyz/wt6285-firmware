#!/bin/sh
# 重启 4G 模块：AT+CFUN=1,1 软复位，等待重新枚举后恢复 SIM 选择
# 用法: modem-restart.sh [--check]

DEV="$(uci -q get lpac.main.at_device || echo /dev/ttyUSB1)"
SEL="$(uci -q get ec200a.ec200a.sim_sel || echo 0)"

if [ "$1" = "--check" ]; then
	echo "dev=$DEV sim_sel=$SEL"
	exit 0
fi

logger -t wt6285 "modem restart: begin (dev=$DEV sim_sel=$SEL)"

# 软复位模块（不断 USB 供电）
/usr/bin/sms_tool -d "$DEV" at "AT+CFUN=1,1" >/dev/null 2>&1

# 等模块重新枚举
i=0
while [ $i -lt 30 ]; do
	sleep 2
	i=$((i + 1))
	[ -e "$DEV" ] && break
done

# 恢复卡槽选择（会写 GPIO）
[ -x /usr/libexec/wt6285/sim.sh ] && /usr/libexec/wt6285/sim.sh "$SEL" >/dev/null 2>&1

# 重新拉起 WAN
ifup wan >/dev/null 2>&1

logger -t wt6285 "modem restart: done after ${i}0s"
exit 0
