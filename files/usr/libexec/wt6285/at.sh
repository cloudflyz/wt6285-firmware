#!/bin/sh
# 通用 AT 执行：at.sh "AT+CSQ"
# 串口互斥：本脚本与 at.sh / esim.lua / smsd.sh 共享同一个 AT 口
exec 9>/var/lock/wt6285-at.lock
flock -x 9
DEV="$(uci -q get lpac.main.at_device || echo /dev/ttyUSB1)"
exec /usr/bin/sms_tool -d "$DEV" at "$1"
