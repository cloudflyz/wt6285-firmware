# wt6285-firmware

NRadio WT6285（MT7628AN，16M flash / 128M RAM）自用固件，基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 构建，目标：

- 最新 lean master（每次构建记录 upstream SHA）
- 双内核产物：5.10（稳定）/ 6.18（experimental）
- 集成 **lpac**（实体 eUICC 的 profile 管理，AT 后端）
- 集成 **sms-tool**（短信收发，来自 `coolsnowwolf/packages` 的 `utils/sms-tool`，Apache-2.0）+ 通知脚本
- 不包含 ssr-plus
- 构建全部在 GitHub Actions 完成，产物带 SHA256

## 设备事实

|项|值|
|---|---|
|SoC|MediaTek MT7628AN ver:1 eco:2|
|目标|ramips/mt76x8 · mipsel_24kc|
|Flash|16M（firmware 0xf70000，overlay 5.7M）|
|4G 模块|Quectel 2c7c:6005（EC200A 系），ECM 网卡 usb0|
|AT 口|/dev/ttyUSB1|
|SIM|外置卡 + 内置 SIM1/SIM2，GPIO 切换|

## 目录

```
configs/     defconfig（5.10 与 6.18）
files/       rootfs overlay（uci 默认值、脚本、init.d）
package/     自维护包（lpac 等）
upstream.lock  pinned lean commit
docs/        设备笔记、备份与回滚、验证清单
```

## 构建

GitHub Actions → `build` workflow → Run workflow。产物为 `wt6285-<kernel>-<sha>.bin` + `SHA256SUMS.txt`。

## 刷机

```sh
sysupgrade -n /tmp/wt6285-5.10-<sha>.bin
```

刷机前必须完成 `docs/backup.md` 里的备份。

## 状态

- [x] P0 设备备份与脚本归档
- [ ] P1 CI 空构建
- [ ] P2 集成 lpac + sms-tool
- [ ] P3 实机验证
- [ ] P4 固化文档与检查
