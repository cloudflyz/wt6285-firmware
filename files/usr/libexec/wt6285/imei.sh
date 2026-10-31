#!/bin/sh
# WT6285 IMEI helper
# 重写自原厂 /usr/share/moimei（该二进制仅做 AT+EGMR=1,7 透传）
# 用法: imei.sh read | imei.sh write <15位数字>
#
# 注意: 修改 IMEI 可能违反当地法规，仅在自有设备上用于恢复/排障。

AT_PORT="${WT6285_AT_PORT:-/dev/ttyUSB1}"
SMS_TOOL="${WT6285_SMS_TOOL:-/usr/bin/sms_tool}"

at() {
	"$SMS_TOOL" -d "$AT_PORT" at "$1" 2>/dev/null | tr -d '\r'
}

read_imei() {
	at 'AT+EGMR=0,7' | sed -n 's/.*+EGMR: *"\([0-9]\{15\}\)".*/\1/p'
}

write_imei() {
	imei="$1"
	case "$imei" in
		[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;;
		*) echo "IMEI 必须是 15 位数字" >&2; return 2 ;;
	esac
	out="$(at "AT+EGMR=1,7,\"$imei\"")"
	echo "$out" | grep -q '^OK' || { echo "写入被拒: $out" >&2; return 1; }
	uci set ec200a.ec200a.IMEI="$imei"
	uci set ec200a.ec200a.modify_imei=1
	uci commit ec200a
	at 'AT+CFUN=1,1' >/dev/null 2>&1
	sleep 8
	now="$(read_imei)"
	[ "$now" = "$imei" ] || { echo "回读不一致: ${now:-空}" >&2; return 1; }
	echo "OK $now"
}

case "$1" in
	read) read_imei ;;
	write) [ -n "${2:-}" ] || { echo "用法: imei.sh write <15位数字>" >&2; exit 2; }; write_imei "$2" ;;
	*) echo "用法: imei.sh read | imei.sh write <15位数字>" >&2; exit 2 ;;
esac
