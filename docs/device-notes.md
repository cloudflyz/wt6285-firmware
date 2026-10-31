# WT6285 设备笔记

## 硬件

- SoC：MediaTek MT7628AN ver:1 eco:2（MIPS 24KEc）
- 目标：`ramips/mt76x8`，`mipsel_24kc`，musl
- Flash：16M SPI-NOR；firmware 分区 `0xf70000`（约 15.4M），overlay `0x5b0000`（5.7M）
- RAM：128M
- 4G 模块：Quectel `2c7c:6005`（EC200A 系），ECM 模式，`usb0` 作为 WAN
- 串口：`ttyUSB0/1/2`（option 驱动）；**AT 口为 `/dev/ttyUSB1`**

## 分区表（出厂固件）

```
mtd0 u-boot    0x000000 0x030000
mtd1 kpanic    0x030000 0x010000
mtd2 factory   0x040000 0x010000   ← WiFi 校准，勿动
mtd3 firmware  0x050000 0xf70000
mtd7 bdinfo    0xfe0000 0x010000
mtd8 reserve   0xff0000 0x010000
```

## GPIO（来自 DTS）

|标签|GPIO|有效电平|用途|
|---|---|---|---|
|`cpe-pwr`|41|低有效|模块电源|
|`cpe-sel0`|40|高有效|SIM 选择|
|`cpe-sel1`|44|低有效|SIM 选择|

SIM 选择真值（由 `ec200a.sh` 决定，脚本内注释里的 GPIO 编号是错的，以标签为准）：

|sim_sel|含义|cpe-sel0|cpe-sel1|
|---|---|---|---|
|0|外置 SIM|1|0|
|1|内置 SIM1|0|1|
|2|内置 SIM2|0|0|

切换后需 `AT+CFUN=1,1` 让模块重新初始化，结果缓存在 `/tmp/Sim_Sel` 避免每次开机重复复位。

## 原厂脚本行为

- `/etc/init.d/ec200a`（START=80）
  - `start`：`moat "AT+QNETDEVCTL=3,1"` → `ec200a.sh`
  - `restart`：`moat "AT+CFUN=1,1"` → `ec200a.sh`
  - `check_status`：imei/iccid/isp/band/signal/imsi/cgmr/cellid/sim_sel/status
  - `status` 以 `USB PID 6005` 判断模块是否存在
- `/usr/share/ec200a.sh`：IMEI 改写（`/usr/share/moimei`）、锁频（`AT+QCFG=band,0,<hex>`）、SIM 选择（GPIO + `CFUN`）
- `/usr/share/moat`：3.4K 的 musl ELF，硬编码 `/dev/ttyUSB1`，作用只是“发一条 AT 并打印返回”
- `/etc/init.d/gpio_switch`：通用 sysfs GPIO 导出；新固件可直接用 DTS 的 export 标签替代
- `/etc/init.d/autoreboot`：写 cron 行实现定时重启
- `sms_tool`：`/etc/config/sms_tool` 四个端口均指向 `ttyUSB1`，存储 `SM`

## 迁移结论

- 不需要 `moat`：用 `sms_tool at` 或 `chat` 替代
- `ec200a.sh` 重写约 40 行：GPIO 选择 + `AT+CFUN=1,1` + `usb0` 上跑 dhcp client
- 若不需要改写 IMEI，可完全去掉 `moimei`
- 必须保留：`kmod-usb-serial-option`、`kmod-usb-net-cdc-ether`、`usb-modeswitch`、`curl`、`ca-bundle`

## 短信栈选型（2026-10-31 定）

- 使用 `coolsnowwolf/packages` 的 `utils/sms-tool`（不是 vendor 二进制）
- 上游源码：`obsy/sms_tool`，pin 在 `f07699ab5189656f595ffa75872c8938bf4b40ac`（2022-03-21）
- 许可证 Apache-2.0，无额外 DEPENDS，编出来就是单个 `sms_tool`
- 配置里加 `CONFIG_PACKAGE_sms-tool=y` 即可，随 lean 的 feeds 一起进固件
- AT 口仍用 `/dev/ttyUSB1`，参数沿用原固件 `/etc/config/sms_tool`
- LuCI 页面不强制：命令行 + 通知脚本（Bark/Telegram）足够
