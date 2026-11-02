# wt6285-firmware

NRadio WT6285（鲲鹏cc）自用固件，基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 构建。

目标：把一块 16M flash 的 MT7628AN 4G 路由，做成能管 eSIM、收发短信、可视化设置的自用设备。

## 特性

- **双内核**：5.10（稳定，默认）/ 6.18（experimental，ramips testing 通道）
- **eSIM 管理**：集成 `lpac`，AT 后端，可直接下载 / 启用 / 删除 profile
- **短信收发**：`sms-tool` + 通知脚本
- **4G 拨号**：`quectel-cm-5G`，兼容 EC200A 系模块
- **LuCI 面板**：状态 / SIM / eSIM / 短信 / 设置（含 IMEI 修改，二次确认）
- **构建可溯源**：固定 lean commit，CI 全程自动化，产物附 SHA256 与 buildinfo
- **TLS 统一**：wpad、libopenssl、curl、wget 共用一套 OpenSSL 栈

## 硬件

| 项 | 值 |
| --- | --- |
| SoC | MediaTek MT7628AN ver:1 eco:2 |
| 目标 | `ramips/mt76x8` · `mipsel_24kc` |
| Flash | 16 M（firmware 分区 `0xf70000` = 15.44 MiB） |
| RAM | 128 M |
| 4G 模块 | Quectel `2c7c:6005`（EC200A 系），ECM 网卡 `usb0` |
| AT 口 | `/dev/ttyUSB1` |
| SIM | 外置卡 + 内置 SIM1/SIM2，GPIO 切换 |
| 无线 | MT7628 内置 2.4G（`kmod-mt7603`） |

## 内置组件

| 组件 | 版本 | 说明 |
| --- | --- | --- |
| `lpac` | 2.3.0 | eUICC LPA，AT 后端，SM-DP+ 走 curl |
| `quectel-cm-5G` | 1.6.4 | Quectel 模块拨号（源自 Lienol/openwrt qmodem） |
| `sms-tool` | 2022-03-21 | 短信收发（源自 `coolsnowwolf/packages` `utils/sms-tool`） |
| `luci-app-wt6285` | — | 状态 / SIM / eSIM / 短信 / 设置面板 |

TLS 栈：`wpad-basic-openssl` + `libopenssl` + `openssl-util` + `wget-ssl` + `LIBCURL_OPENSSL`，与 `curl`、`lpac` 共用一套 OpenSSL。

## 内核

| 配置 | 内核 | 用途 |
| --- | --- | --- |
| `configs/wt6285-lite.config` | 5.10.273 | 稳定版，默认 |
| `configs/wt6285-6.18.config` | 6.18.60 | experimental，ramips `KERNEL_TESTING_PATCHVER` |
| `configs/wt6285.config` | 5.10.273 | 完整版（含 usb-modeswitch 等） |

6.18 配置文件里显式写了 `CONFIG_TESTING_KERNEL=y`——**这一行不能省**，否则 `make defconfig` 会静默回落到 5.10。

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
```

注意两点：刷机时勾选「保留配置」则沿用旧 IP；设备已初始化过则脚本不再执行（需 `firstboot` 重置）。

## 构建

### GitHub Actions

`.github/workflows/build.yml`，`workflow_dispatch` 手动触发，matrix 并行构建 5.10 与 6.18。

- 按 `upstream.lock` 固定 lean commit
- `feeds update -a` / `install -a` → 拷入自定义包 → 应用 `files/` overlay
- `make defconfig` 后断言 4 个自定义包符号，缺一个即失败
- 编译完成后按 `wt6285-<kver>-<sha>-*` 重命名，生成 `SHA256SUMS.txt` 与 `buildinfo.txt`

实测单轮：5.10 约 72 分钟，6.18 约 76 分钟（上限 300 分钟）。

### 本地

```sh
# 准备：lede 源码已就位
cp configs/wt6285-6.18.config lede/.config
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
| `wt6285-6.18-1e71a21-...-squashfs-sysupgrade.bin` | 12,321,570 B | `54d5f134…5a56f983` |
| `wt6285-5.10-1e71a21-...-squashfs-sysupgrade.bin` | 10,748,706 B | `a1b617bf…e06d35` |

发布于 [Releases](https://github.com/cloudflyz/wt6285-firmware/releases)，附 `SHA256SUMS.txt` 与 `buildinfo.txt`（lean SHA / 内核 / 构建时间 / runner）。

## 校验

```sh
sha256sum -c SHA256SUMS.txt
```

## 刷机

```sh
sysupgrade -n /tmp/wt6285-6.18-1e71a21-...-squashfs-sysupgrade.bin
```

- 刷前完成 `docs/backup.md` 的备份
- **刷完立即设置 root 密码**：OpenWrt 默认 root 无密码，LAN 内可直接登录
- 6.18 出问题直接回刷 5.10 版

## 已知限制

- **6.18 是 experimental**：走 ramips testing 通道，上游可能变更。`upstream.lock` 固定 SHA 保证可复现，但升级 lean 时需重新验证补丁是否仍可应用。
- **镜像不是字节级可复现**：本地与 CI 编译路径不同（`/root/...` vs `/home/runner/...`），路径字符串进入内核导致哈希不同，功能等价。需要字节一致得统一构建目录并设 `SOURCE_DATE_EPOCH`。
- **体积余量有限**：6.18 镜像 11.75 MiB / 分区 15.44 MiB，剩约 3.69 MiB。加包前先算余量。
- **lpac 依赖名易漂移**：目前 `PKG_BUILD_DEPENDS:=curl`（源包名）+ `DEPENDS:=+libcurl`（二进制包名）。上游 curl 包已在新版本改名 `libcurl4`，升级 lean 时两个名字要一起改，否则 lpac 会静默失去 https 能力。

## 构建优化记录（2026-11-02）

| 问题 | 处理 |
| --- | --- |
| `download.pl` 无超时，源站挂死时静默空转 48 分钟 | 打补丁 `--speed-limit 2048 --speed-time 45 --max-time 900 --retry 3`，并写入 `scripts/build-local.sh` 与 CI |
| `broadcom-wl` 源返回 410、`backports` 源 0 字节 | 从 `sources.openwrt.org` 补齐并校验 hash |
| `lpac` 报 `build dependency on 'libcurl', which does not exist` | `PKG_BUILD_DEPENDS` 由 `libcurl` 改为源包名 `curl` |
| 下载缓存在 `lede/dl`，被 `dirclean` 清空 | 外置 `DL_DIR`，528 MB 缓存长期复用 |
| CI 缓存 key 含 `configs/**`，改配置即重下 1 GB | 只按 `upstream.lock` 计算 |
| 5.10 与 6.18 产物同名互相覆盖 | 本地与 CI 均按 `wt6285-<kver>-<sha>-*` 命名 |
| 6.18 配置缺 `CONFIG_TESTING_KERNEL=y`，实际编出 5.10 | 写入配置并断言 |
| 首版混入 Lean 默认选中的非预期包 | 只写 `CONFIG_DEFAULT_... is not set` 只能关掉默认选中，须写 `CONFIG_PACKAGE_... is not set` 才真正排除 |
| TLS 栈混用 mbedtls / openssl | 三份配置统一到 OpenSSL |
| CI matrix 无 6.18 任务 | 增加 `kver: "6.18"` 条目 |

## 目录

```
configs/       defconfig（5.10 / 6.18 / 完整版）
files/         rootfs overlay（uci-defaults、脚本、init.d、hotplug）
package/       自维护包：lpac、quectel-cm-5g、luci-app-wt6285
scripts/       本地构建入口 build-local.sh
docs/          设备笔记、备份与回滚、验证清单、LuCI 规划
upstream.lock  pinned lean commit
```

## 状态

- [x] P0 设备备份与脚本归档
- [x] P1 CI 构建（5.10 + 6.18 双 job 通过）
- [x] P2 集成 lpac + sms-tool + quectel-cm-5G
- [x] P3 LuCI 页面（状态 / SIM / eSIM / 短信 / 设置）
- [x] P4 本地双内核编译通过，产物归档
- [x] P5 Release 发布与文档固化
- [ ] P6 实机刷写验证（4G 拨号 / 短信 / eSIM / WiFi）

## License

自用项目。集成的第三方组件遵循各自许可：`lpac` AGPL-3.0-only / LGPL-2.0-only，`sms-tool` Apache-2.0，`quectel-cm` 见上游。
