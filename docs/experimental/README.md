# 实验性补丁存档

这里放验证过但**未采用**的补丁，不参与构建，仅作记录，避免以后重复踩坑。

## lpac-at-csim-fallback.patch

**目标**：让 lpac 的 AT 后端在模块不支持 `AT+CCHO`/`AT+CCHC`/`AT+CGLA` 时，退化为 `AT+CSIM` 收发 APDU（如 Quectel EC200A）。

**结论：不可用，已回退。**

机制上补丁本身是通的，几次迭代也修掉了真实 bug：

- 探测改用真实 APDU（模块对 `AT+CSIM=?` 不应答）
- 命令必须一次 `fwrite` 写完（否则被拆成 `AT+C0`）
- 读到 `OK`/`ERROR` 才返回（残留 `OK` 会污染下一条命令）
- SELECT 后要把 `61xx` 的 FCI 取完（否则后续 ES10 指令失步）

但实测卡在模块固件层：

- PDP 激活后 `AT+CSIM` 经常无应答或被截断
- 关闭 WAN 后能推进到 `es10c_get_eid`，再往后仍失败，`profile list` 偶发段错误
- `AT+CGATT=0` 会直接把 EC200A 的 AT 通道弄哑，需硬复位恢复

**正路**：USB CCID 读卡器 + `pcscd` + lpac 的 `pcsc` 后端，逻辑通道由读卡器提供，与 4G 数据连接互不干扰。

补丁保留在此，若以后换用支持逻辑通道的模块（如 EC25/EC21 某些固件）可再评估。
