#!/bin/sh
# WT6285 本地编译入口（CI 走 .github/workflows/build.yml，两处逻辑保持一致）
# 用法: scripts/build-local.sh [make 目标...]     不带参数 = 全量 world，并归档产物
set -e

REPO=$(cd "$(dirname "$0")/.." && pwd)
LEDE=${LEDE:-/root/wt6285-build/lede}
DL_CACHE=${DL_CACHE:-/root/wt6285-build/dl-cache}
OUT_DIR=${OUT_DIR:-/root/wt6285-build/out}
JOBS=${JOBS:-8}

export FORCE_UNSAFE_CONFIGURE=1

# 本机 mihomo 代理（USE_PROXY=0 可关）
if [ "${USE_PROXY:-1}" = "1" ]; then
	export http_proxy=http://127.0.0.1:7890
	export https_proxy=$http_proxy
	export HTTP_PROXY=$http_proxy
	export HTTPS_PROXY=$http_proxy
	export no_proxy=localhost,127.0.0.1,192.168.0.0/16,::1
	export NO_PROXY=$no_proxy
fi

# 1) download.pl 超时补丁：源站挂死时快速放弃并换源（幂等）
DL_PL="$LEDE/scripts/download.pl"
if [ -f "$DL_PL" ] && ! grep -q -- "--speed-time 45" "$DL_PL"; then
	cp -a "$DL_PL" "$DL_PL.bak-$(date +%Y%m%d-%H%M%S)"
	sed -i "s|curl -f --connect-timeout 20 --retry 5 --location|curl -f --connect-timeout 20 --retry 3 --location --speed-limit 2048 --speed-time 45 --max-time 900|" "$DL_PL"
	echo "[build-local] patched download.pl timeouts"
fi

# 2) 下载缓存放在 lede 之外，make dirclean 不会清掉
mkdir -p "$DL_CACHE"

make -C "$LEDE" DL_DIR="$DL_CACHE" -j"$JOBS" "$@"

# 3) 全量构建后按内核版本重命名归档，避免 5.10 / 6.18 同名产物互相覆盖
[ $# -eq 0 ] || exit 0

BIN="$LEDE/bin/targets/ramips/mt76x8"
[ -d "$BIN" ] || exit 0

if grep -q "^CONFIG_LINUX_6_18=y" "$LEDE/.config"; then
	KVER=6.18
elif grep -q "^CONFIG_LINUX_5_10=y" "$LEDE/.config"; then
	KVER=5.10
else
	KVER=unknown
fi

SHA=$(cut -c1-7 "$REPO/upstream.lock" 2>/dev/null || echo nolock)
DEST="$OUT_DIR/wt6285-$KVER-$SHA"
mkdir -p "$DEST"

for f in "$BIN"/*.bin; do
	[ -e "$f" ] || continue
	cp -f "$f" "$DEST/wt6285-$KVER-$SHA-$(basename "$f")"
done

if ls "$DEST"/*.bin >/dev/null 2>&1; then
	( cd "$DEST" && sha256sum *.bin > SHA256SUMS.txt )
	echo "[build-local] 产物已归档：$DEST"
	ls -lh "$DEST"
fi
