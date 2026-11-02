# configs

这里放 `make defconfig` 导出的配置：

- `wt6285-lite.config` — 精简版（默认，5.10 内核）
- `wt6285.config` — 完整版（含 usb-modeswitch 等）

生成方式（在 lede 源码目录）：

```sh
make menuconfig          # 选 Target: ramips / mt76x8 / NRadio WT6285
./scripts/diffconfig.sh > ../configs/wt6285-lite.config
```
