#!/bin/sh
# 通用 AT 执行：at.sh "AT+CSQ"
DEV="$(uci -q get lpac.main.at_device || echo /dev/ttyUSB1)"
exec /usr/bin/sms_tool -d "$DEV" at "$1"
