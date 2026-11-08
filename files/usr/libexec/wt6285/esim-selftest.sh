#!/bin/sh
# esim-selftest.sh —— eSIM 功能回归自检
#
# 用途：每次改动后先跑一遍，确认核心链路没被改坏。
# 只做只读与"预期失败"的用例，不会改动卡上的 profile。
#
# 用法：esim-selftest.sh [--full]
#   --full 额外跑一次真实的 lpac chip info（约 13 秒）

SCRIPT=/usr/libexec/wt6285/esim.lua
PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ✓ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

check() {
	desc=$1; expect=$2; out=$3
	case "$expect" in
		contains:*)
			case "$out" in *"${expect#contains:}"*) ok "$desc" ;; *) bad "$desc（实际: $(echo "$out" | head -c 80)）" ;; esac
			;;
		notcontains:*)
			case "$out" in *"${expect#notcontains:}"*) bad "$desc（不该出现: ${expect#notcontains:}）" ;; *) ok "$desc" ;; esac
			;;
	esac
}

echo "=== eSIM 自检 $(date '+%F %T') ==="

echo "[1] 缓存读取（info）"
# 首次调用可能触发恢复链（清通道 2s + 重试 13s + CFUN 19s + 再试 13s），
# 单步上限必须大于这条链，否则会误判为失败。
OUT=$(timeout 180 lua "$SCRIPT" info 2>&1)
check "info 返回 eid 或已有缓存" "contains:eid=" "$OUT"

echo "[2] profile 列表"
OUT=$(timeout 180 lua "$SCRIPT" list 2>&1)
check "list 返回 count=" "contains:count=" "$OUT"
case "$OUT" in
	*"|01|"*|*"|00|"*) ok "状态字段为 01/00 口径" ;;
	*) bad "状态字段不是 01/00（页面会误显示禁用）" ;;
esac

echo "[3] 通知列表（缓存或实时）"
OUT=$(timeout 180 lua "$SCRIPT" notif-list 2>&1)
check "notif-list 不报 euicc_init" "notcontains:euicc_init" "$OUT"

echo "[4] 下载参数校验（预期失败，不改卡）"
OUT=$(timeout 30 lua "$SCRIPT" download 2>&1)
check "缺参返回 missing_params" "contains:missing_params" "$OUT"

echo "[5] 重命名参数校验（预期失败）"
OUT=$(timeout 30 lua "$SCRIPT" rename 1234 x 2>&1)
check "非法 ICCID 返回 badiccid" "contains:badiccid" "$OUT"

echo "[6] 通知删除参数校验（预期失败）"
OUT=$(timeout 30 lua "$SCRIPT" notif-remove 2>&1)
check "缺 seq 返回 badseq" "contains:badseq" "$OUT"

echo "[7] 业务锁"
# 注意：这里必须用不存在的 ICCID。早先版本用了真实 ICCID，
# 一旦锁判定失效就会真的去删用户的 profile（实测触发过一次，
# 仅因该 profile 处于启用态被卡拒绝而未删成功）。自检脚本绝不能有这种副作用。
mkdir -p /var/lock/wt6285-esim.busy 2>/dev/null
OUT=$(timeout 30 lua "$SCRIPT" delete 000000000000000000 2>&1)
check "锁被占用时返回 busy" "contains:busy" "$OUT"
rm -rf /var/lock/wt6285-esim.busy 2>/dev/null

if [ "$1" = "--full" ]; then
	echo "[8] lpac 直连（约 13 秒）"
	OUT=$(timeout 60 /usr/bin/lpac-at chip info 2>&1)
	check "lpac chip info 返回 success" "contains:success" "$OUT"
fi

echo "=== 结果：通过 $PASS，失败 $FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
