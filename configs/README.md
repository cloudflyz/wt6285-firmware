# configs

这里放 `make defconfig` 导出的精简配置：

- `wt6285.config` — 默认内核（5.10）
- `wt6285-6.18.config` — 实验内核（构建时额外追加 `CONFIG_TESTING_KERNEL=y`）

生成方式（在 lede 源码目录）：

```sh
make menuconfig          # 选 Target: ramips / mt76x8 / NRadio WT6285
./scripts/diffconfig.sh > ../configs/wt6285.config
```
