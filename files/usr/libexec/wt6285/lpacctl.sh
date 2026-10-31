#!/bin/sh
# lpac 封装：自动带上 AT 设备
DEV="$(uci -q get lpac.main.at_device || echo /dev/ttyUSB1)"
export LPAC_APDU_AT_DEVICE="$DEV"
exec /usr/bin/lpac "$@"
