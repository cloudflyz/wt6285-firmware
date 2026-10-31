# files

rootfs overlay：构建时复制到 `package/base-files/files/`。

计划内容：
- `etc/uci-defaults/` — 首次启动配置（LAN 192.168.8.1、WAN=usb0、时区）
- `etc/init.d/` — 模块初始化、SIM 切换、定时重启
- `usr/bin/` — 通知脚本、切卡脚本
