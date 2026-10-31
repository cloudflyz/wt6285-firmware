# 刷机后验收清单（P4）

## 1. 启动
- [ ] 串口 / LED 显示正常启动
- [ ] LAN 口可访问 `http://192.168.8.1`
- [ ] `uname -a` 版本与构建 buildinfo 一致

## 2. 内网
- [ ] DHCP 分配地址正常（客户端能拿到 192.168.8.x）
- [ ] WiFi 热点出现，能连上并获取地址
- [ ] LuCI 页面可登录（默认密码已修改）

## 3. 模块
- [ ] `ls /dev/ttyUSB*` 出现 0/1/2
- [ ] `sms_tool -d /dev/ttyUSB1 at AT+CGSN` 返回 IMEI
- [ ] `AT+CPIN?` 为 READY（插卡后）
- [ ] `AT+CSQ` 有信号值

## 4. 数据
- [ ] `usb0` 获取到 IPv4
- [ ] `ping 223.5.5.5` 通
- [ ] 断开模块再上电，hotplug 能自动恢复

## 5. 短信
- [ ] 收：发送一条测试短信，页面/`sms_tool recv` 可见
- [ ] 发：页面发送成功，对方收到
- [ ] 通知：Bark/Telegram 收到推送

## 6. eSIM
- [ ] `lpacctl.sh chip info` 返回 eUICC 信息
- [ ] `profile list` 能列出已有 profile
- [ ] 切换 profile 后模块复位、重新注册
- [ ] 下载新 profile 成功（时间正确前提下）

## 7. 硬件
- [ ] LED 状态正常
- [ ] SIM 三选一切换生效（外置/内置1/内置2）
- [ ] 温度正常，无异常负载

## 8. 回滚
- [ ] Breed 可进入，能刷回旧固件
