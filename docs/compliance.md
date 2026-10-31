# 合规与安全说明

## IMEI 修改

本仓库保留 IMEI 修改能力（`imei.sh`、LuCI 设置页），但：

- 修改 IMEI 在多数国家和地区受法律限制，可能构成违法
- 写错会导致模块无法注册，甚至需要返厂
- 本项目默认不预填任何 IMEI，页面需二次确认
- 使用者需自行承担全部责任

## 管理面

- 默认仅监听 LAN，勿将 LuCI/SSH 暴露到公网
- 首次登录后立即修改 root 密码
- 若添加了外部 SSH 公钥用于调试，交付前请移除

## 第三方代码

- `package/quectel-cm-5g/src` 来自 Lienol/openwrt qmodem，NOTICE 允许修改与再分发
- lpac 为 AGPL-3.0
- sms-tool 为 Apache-2.0
