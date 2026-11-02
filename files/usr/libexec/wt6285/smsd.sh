#!/bin/sh
# 轮询新短信并推送通知
# 串口互斥：本脚本与 at.sh / esim.lua / smsd.sh 共享同一个 AT 口
exec 9>/var/lock/wt6285-at.lock
flock -x 9
DEV="$(uci -q get lpac.main.at_device || echo /dev/ttyUSB1)"
URL="$(uci -q get sms_tool.general.notify_url)"
EN="$(uci -q get sms_tool.general.notify_enabled)"
[ "$EN" = "1" ] || exit 0
[ -n "$URL" ] || exit 0

/usr/bin/sms_tool -d "$DEV" recv -j 2>/dev/null | while read -r line; do
	[ -n "$line" ] || continue
	text=$(echo "$line" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p')
	num=$(echo "$line" | sed -n 's/.*"number":"\([^"]*\)".*/\1/p')
	[ -n "$text" ] || continue
	curl -fsS -m 10 -X POST "$URL" \
		-H 'Content-Type: application/json' \
		-d "{\"title\":\"短信 $num\",\"body\":\"$text\"}" >/dev/null 2>&1
done
