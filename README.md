# wt6285-firmware

NRadio WT6285（鲲鹏cc）自用固件，基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 构建。

目标：把一块 16M flash 的 MT7628AN 4G 路由，做成能管 eSIM、收发短信、可视化设置的自用设备。

## 特性

- **内核**：5.10.273（长期维护版，ramips 默认）
- **eSIM 完整管理**：内置 `lpac`（AT 后端）+ `esim.lua` 封装，支持读 EID、列 profile、启用/禁用、重命名、删除、下载新 profile（SM-DP+ / 整串 LPA）、通知逐条发送与删除；`/usr/bin/lpac-at` 负责让出串口并自带两级自愈
- **短信收发**：`sms-tool` + 通知脚本
- **4G 拨号**：`quectel-cm-5G`，兼容 EC200A 系模块
- **LuCI 面板**：状态 / eSIM / 工具（SIM 选择、短信、AT 指令、设置）四块，含 IMEI 修改与软硬复位
- **Vantage 主题 + 仪表盘**：控制台风格界面，`Ctrl+K` 命令面板，设备/上行/射频/终端概览
- **构建可溯源**：固定 lean commit，CI 全程自动化，产物附 SHA256 与 buildinfo
- **TLS 统一**：wpad、libopenssl、curl、wget 共用一套 OpenSSL 栈

## 硬件

| 项 | 值 |
| --- | --- |
| SoC | MediaTek MT7628AN ver:1 eco:2 |
| 目标 | `ramips/mt76x8` · `mipsel_24kc` |
| Flash | 16 M（firmware 分区 `0xf70000` = 15.44 MiB） |
| RAM | 128 M |
| 4G 模块 | Quectel `2c7c:6005`（EC200A 系），组成可为 RNDIS(usb0) / ECM / MBIM |
| AT 口 | 随 USB 组成自动探测（MBIM/ECM → `/dev/ttyACM*`，RNDIS → `/dev/ttyUSB*`） |
| SIM | 外置卡 + 内置 SIM1/SIM2，GPIO 切换 |
| 无线 | MT7628 内置 2.4G（`kmod-mt7603`） |

## 内置组件

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| `esim.lua` | 自研 | 裸 APDU 管理 eSIM：EID / profile 列表 / 启用 / 禁用 |
| `quectel-cm-5G` | 1.6.4 | Quectel 模块拨号（源自 Lienol/openwrt qmodem） |
| `sms-tool` | 2022-03-21 | 短信收发（源自 `coolsnowwolf/packages` `utils/sms-tool`） |
| `luci-app-wt6285` | — | 状态 / SIM / eSIM / 短信 / AT 指令 / 设置 |
| `luci-theme-vantage` | 1.0.12 | 默认主题（控制台风格，明暗双模） |
| `luci-app-vantage` | 1.0.12 | 仪表盘（设备 / 上行 / 射频 / SSID / 终端） |

TLS 栈：`wpad-basic-openssl` + `libopenssl` + `openssl-util` + `wget-ssl` + `LIBCURL_OPENSSL`，与 `curl`、`esim.lua` 的 HTTPS 依赖共用一套 OpenSSL。

## 内核

| 配置 | 内核 | 用途 |
| --- | --- | --- |
| `configs/wt6285.config` | 5.10.273 | 标准版，默认（精简组件已合并） |
| `configs/wt6285.config` | 5.10.273 | 完整版（含 usb-modeswitch 等） |

## 首次启动默认值

来自 `files/etc/uci-defaults/99-wt6285`，仅在 `/etc/config/network` 不存在时执行一次：

```
LAN IP      192.168.8.1 / 255.255.255.0
hostname    WT6285
时区        CST-8 / Asia/Shanghai
NTP         ntp.aliyun.com、ntp.tencent.com（不对外提供 NTP 服务）
WAN         proto=dhcp, device=usb0
WAN6        proto=dhcpv6, device=usb0
dhcp        dhcp.wan.ignore=1
root 登录   root / password（lean default-settings 的初始密码，刷完立即改）
无线 SSID   LEDE（lean 默认，未预设密码）
默认主题    Vantage（luci.main.mediaurlbase=/luci-static/vantage）
```

注意三点：

- 刷机时勾选「保留配置」则沿用旧 IP；设备已初始化过则脚本不再执行（需 `firstboot` 重置）。
- **root 初始密码是 `password`**（来自 lean 的 `default-settings`，不是空密码）。镜像里 `/etc/shadow` 首次启动前是空哈希，所以直接看镜像会误以为无密码；LuCI 用空密码登录会被拒。
- 首次登录后立刻改密码：LuCI「系统 → 管理权」，或 SSH 里执行 `passwd`。

## 构建

### GitHub Actions

`.github/workflows/build.yml`，`workflow_dispatch` 手动触发，matrix 构建 5.10。

- 按 `upstream.lock` 固定 lean commit
- `feeds update -a` / `install -a` → 拷入自定义包 → 应用 `files/` overlay
- `make defconfig` 后断言 4 个自定义包符号，缺一个即失败
- 编译完成后按 `wt6285-<kver>-<sha>-*` 重命名，生成 `SHA256SUMS.txt` 与 `buildinfo.txt`

实测单轮：约 72 分钟（上限 300 分钟）。

### 本地

```sh
# 准备：lede 源码已就位
cp configs/wt6285.config lede/.config
make -C lede defconfig

# 编译 + 自动归档
JOBS=8 scripts/build-local.sh
```

脚本做三件事：

1. 幂等给 `lede/scripts/download.pl` 打超时补丁
2. 下载缓存指向 `lede/` 之外的目录（`DL_DIR`），`make dirclean` 不会清掉
3. 全量构建后按 `wt6285-<kver>-<sha>-*` 归档到 `out/`，避免两版同名产物互相覆盖

## 产物

| 文件 | 大小 | SHA256 |
| --- | --- | --- |
| `wt6285-5.10-1e71a21-...-squashfs-sysupgrade.bin` | 10,486,562 B | `e0bc092f…e4d8d7` |

发布于 [Releases](https://github.com/cloudflyz/wt6285-firmware/releases)，附 `SHA256SUMS.txt` 与 `buildinfo.txt`（lean SHA / 内核 / 构建时间 / runner）。

## 校验

```sh
sha256sum -c SHA256SUMS.txt
```

## 刷机

```sh
sysupgrade -n /tmp/wt6285-5.10-1e71a21-...-squashfs-sysupgrade.bin
```

- 刷前完成 `docs/backup.md` 的备份
- **刷完立即设置 root 密码**：OpenWrt 默认 root 无密码，LAN 内可直接登录

## 已知限制

- **镜像不是字节级可复现**：本地与 CI 编译路径不同（`/root/...` vs `/home/runner/...`），路径字符串进入内核导致哈希不同，功能等价。需要字节一致得统一构建目录并设 `SOURCE_DATE_EPOCH`。
- **体积余量有限**：5.10 镜像 10.49 MiB / 分区 15.44 MiB，剩约 4.9 MiB。加包前先算余量。
- **eSIM 只能做本地操作**：EC200A 不支持 `AT+CCHO`/`AT+CCHC`/`AT+CGLA`，本机只能走单条 `AT+CSIM`，因此**启用/禁用/列 profile 可以，下载与删除不行**（需要完整 ES10 会话）。下载请用手机 App 或 PC/SC 读卡器。
- **`AT+CGATT=0` 会让 EC200A 失联**：实测该指令会把 AT 通道弄哑、4G 掉线，需硬复位恢复。因此漫游流量熔断不能用它，只能走 netifd 层（`ifdown wan` + APN DONTUSE + nft）。
- **切换 profile 会短暂断网**：启用/禁用后模块需 USB 重枚举才能重新附着，约 30 秒，期间 4G 中断、IP 可能变化（LAN/LuCI 不受影响）。

## 构建优化记录（2026-11-02）

| 问题 | 处理 |
| --- | --- |
| `download.pl` 无超时，源站挂死时静默空转 48 分钟 | 打补丁 `--speed-limit 2048 --speed-time 45 --max-time 900 --retry 3`，并写入 `scripts/build-local.sh` 与 CI |
| `broadcom-wl` 源返回 410、`backports` 源 0 字节 | 从 `sources.openwrt.org` 补齐并校验 hash |
| `lpac` 报 `build dependency on 'libcurl', which does not exist` | `PKG_BUILD_DEPENDS` 由 `libcurl` 改为源包名 `curl` |
| 下载缓存在 `lede/dl`，被 `dirclean` 清空 | 外置 `DL_DIR`，528 MB 缓存长期复用 |
| CI 缓存 key 含 `configs/**`，改配置即重下 1 GB | 只按 `upstream.lock` 计算 |
| 首版混入 Lean 默认选中的非预期包 | 只写 `CONFIG_DEFAULT_... is not set` 只能关掉默认选中，须写 `CONFIG_PACKAGE_... is not set` 才真正排除 |
| TLS 栈混用 mbedtls / openssl | 三份配置统一到 OpenSSL |

## 目录

```
configs/       defconfig（lite / 完整版）
files/         rootfs overlay（uci-defaults、脚本、init.d、hotplug）
package/       自维护包：lpac、quectel-cm-5g、luci-app-wt6285
scripts/       本地构建入口 build-local.sh
docs/          设备笔记、备份与回滚、验证清单、LuCI 规划
upstream.lock  pinned lean commit
```

## 状态

- [x] P0 设备备份与脚本归档
- [x] P1 CI 构建（5.10 job 通过）
- [x] P2 集成 lpac + sms-tool + quectel-cm-5G
- [x] P3 LuCI 页面（状态 / SIM / eSIM / 短信 / 设置）
- [x] P4 本地双内核编译通过，产物归档
- [x] P5 Release 发布与文档固化
- [x] P6 实机验证：4G 拨号、eSIM 读卡与启用禁用、LuCI 各页、软硬复位
- [x] P7 Vantage 主题与仪表盘
- [ ] P8 下载/删除 profile（需 PC/SC 读卡器）

## License

自用项目。集成的第三方组件遵循各自许可：`lpac` AGPL-3.0-only / LGPL-2.0-only，`sms-tool` Apache-2.0，`quectel-cm` 见上游。

## eSIM 能力与限制

固件内置 `lpac`（**AT 后端**，走 `AT+CCHO`/`AT+CGLA`/`AT+CCHC` 逻辑通道），
LuCI 的 eSIM 页面支持：读取 EID、列 profile、启用/禁用、重命名、删除、
下载新 profile（SM-DP+ 地址 + 激活码，支持直接粘贴 `LPA:1$<smdp>$<matching-id>` 整串）、
以及通知的列表/单条发送/单条删除。

### 关键事实

- `AT+CSIM` 这条命令在 EC200A 上**不支持**（返回 `+CME ERROR: 4`），
  所以不要按"裸 APDU"思路排查；逻辑通道那组命令是可用的。
- 插卡必须在**整机断电**状态下进行，热插拔不会重新识别 SIM
  （表现为 `AT+CPIN? → CME ERROR: 10`、`QSIMSTAT 0,0`）。
- AT 口随 USB 组成变化：MBIM/ECM 组成是 `/dev/ttyACM*`，RNDIS 组成是 `/dev/ttyUSB*`，
  复位后编号还会漂移。固件在模块枚举时自动探测并写入
  `lpac.main.at_device` 与 `sms_tool.general.atport`。
- 跑 lpac 前必须让出 AT 口（`wt6285` 服务、`sms_tool`、手工 `cat` 都会占用），
  统一通过 `/usr/bin/lpac-at` 调用：它会停服务、跑完再恢复服务。
- 每次失败的 lpac 都可能漏一个逻辑通道，通道耗尽后只会返回 `euicc_init`；
  这是"卡不支持"的常见误判来源。
- **两级自愈在 `lpac-at` 内部完成**：lpac 失败且输出含 `euicc_init` 时，
  先 `AT+CCHC=1..7` 清通道并重试；仍失败则 `AT+CFUN=0` → 5s → `AT+CFUN=1`
  重初始化 SIM 接口再试。**重试必须在服务仍为 stop 时执行**——早期把重试写在
  调用方（`esim.lua`），那时服务已被 trap 拉起，AT 口被占，清通道与 CFUN
  全部静默失败，表现为"自动恢复从来不生效"。
- 刷机/重启后的**第一次** lpac 调用会走完整恢复链，约 70 秒；之后缓存命中为 0 秒。
  这不是卡顿，是自愈在跑。

### 页面结构

```
移远模块 → WT6285
  ├ 状态        概要 + 信号 + eSIM 摘要（只读缓存，不触发 lpac）
  ├ eSIM        EID / profile 列表 / 启用禁用 / 重命名 / 删除
  │             下载（SM-DP+ 或整串 LPA）/ 通知列表·单条发送·单条删除 / 操作日志
  └ 工具        入口卡片 → SIM 选择 / 短信 / AT 指令 / 设置
```

旧的 `/wt6285/at`、`/sms`、`/sim`、`/settings` 会跳转到「工具」下对应页面。

### 自检与日志

- `/usr/libexec/wt6285/esim-selftest.sh`：7 项回归（info / list / notif / 参数校验 / 业务锁），
  `--full` 额外跑一次真实 lpac。依赖 lpac 的三项超时为 180 秒，
  **必须大于恢复链长度**，否则"正在恢复"会被误判成失败。
- 操作日志落在 `/root/wt6285-esim.log`（重启不丢，超 64KB 轮转为 `.1`），
  记录下载、重命名、启用/禁用、通知发送与删除的请求与结果；eSIM 页面底部直接展示。

### 已知限制

- 本项目的测试卡根证书为 `testrootsmds.gsma.com`（GSMA 测试根），
  **商用运营商的激活码无法下载**；需要测试 SM-DP+ 的激活码或换成商用时证书的 eUICC。
- 启用/禁用会触发模块硬复位（USB 重枚举），期间数据与 AT 都会短暂中断。
- 页面结果缓存 15 分钟；启用/禁用、下载、重命名、删除、通知操作会主动失效缓存。
