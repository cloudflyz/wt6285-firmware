# LuCI 方案（全功能）

目标：所有常用操作都在网页完成，命令行只作兜底。

## 框架选择

- lean 的 `openwrt-25.12` 分支仍带 `modules/luci-compat` 与 `modules/luci-lua-runtime`
- 因此采用 **Lua CBI + luci-compat**：开发量小、25.12 可运行；后续若要迁 JS 框架，接口层已经独立，不影响后端脚本
- 注意：`luci-app-sms-tool` 不在 lean 的 luci 仓库里（404），短信页面需要自己写

## 应用结构（单应用 + 分页）

`luci-app-wt6285`，一个菜单入口，五个标签页：

1. **状态**
   - IMEI / ICCID / IMSI / 运营商 / 注册状态 / 信号（RSRP/RSRQ/CSQ）
   - 频段（`AT+QNWINFO`）、模块型号与固件版本（`ATI`/`AT+CGMR`）
   - usb0 与 WAN 状态、SIM 当前槽位
   - 一键刷新
2. **SIM**
   - 外置 / 内置 SIM1 / 内置 SIM2 三选一
   - 保存后写 `cpe-sel0` / `cpe-sel1`，执行 `AT+CFUN=1,1`
   - 显示 `/tmp/Sim_Sel` 与当前实际 GPIO 状态
3. **eSIM（lpac）**
   - Profile 列表：ICCID、昵称、状态（enabled/disabled）、SM-DP+ 来源
   - 下载：SM-DP+ 地址 + Activation Code（+ Confirmation Code）
   - 启用 / 禁用 / 删除 / 改名
   - 通知：列出、重发、删除
   - 切换完成后自动复位模块（GPIO `cpe-pwr` 或 `AT+CFUN=1,1`）
4. **短信**
   - 收件箱列表（发件人、时间、内容，JSON）
   - 发送（号码 + 内容，支持长短信）
   - 删除单条 / 全部
   - 通知配置：Bark / Telegram，开关与目标
   - 存储位置与容量（`AT+CPMS?`）
5. **设置**
   - 锁频（band hex + 十进制对照）
   - **IMEI 修改**（保留；页面内有二次确认和风险提示）
   - 定时重启（沿用 autoreboot 逻辑）
   - NTP / 时区（时钟不对会影响 lpac 的 TLS）

## 后端脚本（与页面解耦）

`/usr/libexec/wt6285/`

```
status.sh    汇总 AT 查询，输出 key=value 或 JSON
sim.sh       选择 SIM 槽位 + 复位
at.sh        通用 AT 执行（白名单）
imei.sh      读写 IMEI（写需二次确认）
smsd.sh      短信轮询 + 通知（cron 调用）
lpacctl.sh   lpac 封装：list/download/enable/disable/delete/notify
```

页面只调用这些脚本；脚本同时可命令行使用，便于排障与 CI 测试。

## IMEI 合规提示

代码保留该功能，但：

- 页面需二次确认，并提示“修改 IMEI 可能违反当地法规”
- `docs/` 中记录该风险
- 默认值不预填任何 IMEI
