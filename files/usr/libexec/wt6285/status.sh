#!/bin/sh
# 输出 key=value，供 LuCI / 脚本读取
DEV="$(uci -q get lpac.main.at_device || echo /dev/ttyUSB1)"
S=/usr/bin/sms_tool
at() { "$S" -d "$DEV" at "$1" 2>/dev/null | tr -d '\r'; }

imei=$(at 'AT+CGSN' | grep -oE '[0-9]{15}' | head -1)
iccid=$(at 'AT+QCCID' | sed -n 's/.*+QCCID: *//p' | tr -d '" ')
cops=$(at 'AT+COPS?' | sed -n 's/.*+COPS: *//p')
csq=$(at 'AT+CSQ' | sed -n 's/.*+CSQ: *//p')
qcsq=$(at 'AT+QCSQ' | sed -n 's/.*+QCSQ: *//p')
nwinfo=$(at 'AT+QNWINFO' | sed -n 's/.*+QNWINFO: *//p')
reg=$(at 'AT+CREG?' | sed -n 's/.*+CREG: *//p')
cfun=$(at 'AT+CFUN?' | sed -n 's/.*+CFUN: *//p')

echo "imei=$imei"
echo "iccid=$iccid"
echo "cops=$cops"
echo "csq=$csq"
echo "qcsq=$qcsq"
echo "nwinfo=$nwinfo"
echo "creg=$reg"
echo "cfun=$cfun"
echo "sim_sel=$(uci -q get ec200a.ec200a.sim_sel || echo 0)"
echo "wan_up=$(ubus call network.interface.wan status 2>/dev/null | grep -c '"up": true')"
echo "usb0_ip=$(ifstatus wan 2>/dev/null | grep -o '"address": "[0-9.]*"' | head -1 | cut -d'"' -f4)"
echo "uptime=$(cut -d. -f1 /proc/uptime)"
