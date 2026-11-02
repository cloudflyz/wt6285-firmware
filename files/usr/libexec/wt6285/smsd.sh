#!/bin/sh
# 轮询新短信并推送（Bark 或自定义 webhook），按 index 去重
# 由 cron 每分钟调用一次；串口加锁，避免与 esim.lua / at.sh 抢 AT 口
exec 9>/var/lock/wt6285-at.lock
flock -x 9

DEV="$(uci -q get sms_tool.general.atport || echo /dev/ttyUSB1)"
EN="$(uci -q get sms_tool.general.notify_enabled)"
[ "$EN" = "1" ] || exit 0

URL="$(uci -q get sms_tool.general.notify_url)"
KEY="$(uci -q get sms_tool.general.bark_key)"
if [ -z "$URL" ] && [ -n "$KEY" ]; then
	URL="https://api.day.app/$KEY"
fi
[ -n "$URL" ] || exit 0

STATE=/tmp/smsd.state
touch "$STATE"

/usr/bin/sms_tool -d "$DEV" recv -j 2>/dev/null | while read -r line; do
	[ -n "$line" ] || continue

	idx=$(echo "$line" | sed -n 's/.*"index"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
	text=$(echo "$line" | sed -n 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
	num=$(echo "$line" | sed -n 's/.*"number"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

	[ -n "$idx" ] || continue
	[ -n "$text" ] || continue
	grep -qx "$idx" "$STATE" && continue

	if curl -fsS -m 10 -X POST "$URL" \
		-H 'Content-Type: application/json' \
		-d "{\"title\":\"短信 $num\",\"body\":\"$text\"}" >/dev/null 2>&1; then
		echo "$idx" >> "$STATE"
		logger -t wt6285-sms "pushed sms #$idx from $num"
	fi
done
