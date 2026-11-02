#!/bin/sh
# 轮询新短信并推送（Bark：支持分组与加密；也兼容自定义 webhook）
# cron 每分钟调用；串口加锁，避免与 esim.lua / at.sh 抢 AT 口
exec 9>/var/lock/wt6285-at.lock
flock -x 9

DEV="$(uci -q get sms_tool.general.atport || echo /dev/ttyUSB1)"
EN="$(uci -q get sms_tool.general.notify_enabled)"
[ "$EN" = "1" ] || exit 0

URL="$(uci -q get sms_tool.general.notify_url)"
KEY="$(uci -q get sms_tool.general.bark_key)"
GROUP="$(uci -q get sms_tool.general.bark_group)"
ENC="$(uci -q get sms_tool.general.bark_encrypt)"
CKEY="$(uci -q get sms_tool.general.bark_crypt_key)"

if [ -z "$URL" ] && [ -n "$KEY" ]; then
	URL="https://api.day.app/$KEY"
fi
[ -n "$URL" ] || exit 0

# JSON 字符串转义（反斜杠、双引号、换行、制表）
json_escape() {
	printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}' | sed 's/\\n$//'
}

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

	t=$(json_escape "$text")
	t_num=$(json_escape "$num")

	payload=$(printf '{"title":"短信 %s","body":"%s"' "$t_num" "$t")
	[ -n "$GROUP" ] && payload="$payload,\"group\":\"$(json_escape "$GROUP")\""

	ok=0
	if [ "$ENC" = "1" ] && [ -n "$CKEY" ] && [ -n "$KEY" ]; then
		# Bark 加密推送：AES-128-CBC，key/iv 需 hex 编码；payload 整体加密后作为 ciphertext
		payload="$payload}"
		iv=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
		# 设备上没有 od，用 hexdump（busybox 自带）
		khex=$(printf '%s' "$CKEY" | hexdump -v -e '/1 "%02x"')
		ivhex=$(printf '%s' "$iv" | hexdump -v -e '/1 "%02x"')
		ct=$(printf '%s' "$payload" | openssl enc -aes-128-cbc -K "$khex" -iv "$ivhex" -base64 2>/dev/null | tr -d '\n')
		if [ -n "$ct" ]; then
			curl -fsS -m 10 -X POST "https://api.day.app/push" \
				-H 'Content-Type: application/json' \
				-d "{\"device_key\":\"$KEY\",\"ciphertext\":\"$ct\",\"iv\":\"$iv\"}" >/dev/null 2>&1 && ok=1
		fi
	else
		payload="$payload}"
		curl -fsS -m 10 -X POST "$URL" \
			-H 'Content-Type: application/json' \
			-d "$payload" >/dev/null 2>&1 && ok=1
	fi

	if [ "$ok" = "1" ]; then
		echo "$idx" >> "$STATE"
		logger -t wt6285-sms "pushed sms #$idx from $num (enc=$ENC group=$GROUP)"
	fi
done
