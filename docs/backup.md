# 备份与回滚

## 备份位置

网关主机：`/root/backups/wt6285/<date>/`

|文件|说明|
|---|---|
|`mtd0.bin`|u-boot（0x30000）|
|`mtd1.bin`|kpanic|
|`mtd2.bin`|factory（WiFi 校准，**丢失不可恢复**）|
|`mtd3.bin`|完整 firmware 分区|
|`mtd7.bin`|bdinfo（MAC 等出厂数据）|
|`sysupgrade-backup.tar.gz`|`sysupgrade -b` 标准备份|
|`device-files.tar.gz`|定制脚本与配置|
|`device-files-extra.tar.gz`|`/usr/share/moat`、`ec200a.sh`、`/etc/config/ec200a`|
|`uci-export.txt` / `packages.txt`|配置与包清单|
|`SHA256SUMS`|全部文件校验和|

## 校验

```sh
cd /root/backups/wt6285/<date> && sha256sum -c SHA256SUMS
```

## 刷机前

1. 确认镜像不超过 15.4M（firmware 分区 0xf70000）
2. 确认备份与校验通过，并且至少存在两份副本
3. 通过 SSH 上传到 `/tmp`，执行：

```sh
sysupgrade -n /tmp/wt6285-<kernel>-<sha>.bin
```

`-n` 表示不保留配置；首次切换基线时建议使用。

## 回滚

- 系统还能启动：`sysupgrade -n` 回刷旧镜像
- 无法启动：通过 u-boot / 编程器写回 `mtd3.bin`（firmware），必要时先写 `mtd0.bin`
- **不要随意写 mtd2（factory）**，除非已确认原值损坏
