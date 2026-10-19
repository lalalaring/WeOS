#!/usr/bin/env bash
# 构建主机自检
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/build.env
source "${ROOT_DIR}/config/build.env"

FAIL=0
ok()   { printf '  [ OK ] %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=1; }
warn() { printf '  [WARN] %s\n' "$*"; }

echo "== 1. 构建主机 =="
if [[ ${EUID} -ne 0 ]]; then bad "需要 root 权限（sudo ./build.sh check）"; else ok "root 权限"; fi

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" == "debian" ]]; then
        major="${VERSION_ID%%.*}"
        if [[ "${major:-0}" -ge 12 ]]; then ok "Debian ${VERSION_ID}"; else bad "Debian 版本过低：${VERSION_ID}（需 >= 12）"; fi
    else
        warn "非 Debian 主机（${ID:-unknown}），构建可能失败；建议在 Debian 13 或容器中构建"
    fi
else
    bad "无法读取 /etc/os-release"
fi

echo "== 2. 构建工具 =="
for c in lb debootstrap xorriso mksquashfs rsync gpg curl xz; do
    if command -v "$c" >/dev/null 2>&1; then ok "$c"; else bad "缺少 $c"; fi
done
command -v debmirror >/dev/null 2>&1 && ok "debmirror（快照模式可用）" || warn "未安装 debmirror（仅 snapshot 模式需要）"

if [[ ${FAIL} -eq 1 ]]; then
    echo
    echo "安装缺失依赖："
    echo "  apt install live-build debootstrap xorriso squashfs-tools rsync gnupg curl xz-utils debmirror"
fi

echo "== 3. 磁盘空间 =="
avail_gb=$(df -BG --output=avail "${ROOT_DIR}" 2>/dev/null | tail -1 | tr -dc '0-9')
if [[ -n "${avail_gb}" && "${avail_gb}" -ge 25 ]]; then ok "可用 ${avail_gb} GB"; else bad "可用空间不足（${avail_gb:-?} GB，建议 >= 25 GB）"; fi

echo "== 4. CPU 指令集（内核 ABI ${KERNEL_ABI}）=="
if [[ "${KERNEL_ABI}" == "x64v3" ]]; then
    if grep -qw avx2 /proc/cpuinfo; then ok "支持 AVX2（x64v3 可用）"; else bad "CPU 不支持 AVX2，请把 KERNEL_ABI 改为 x64v2"; fi
elif [[ "${KERNEL_ABI}" == "x64v2" ]]; then
    if grep -qw sse4_2 /proc/cpuinfo; then ok "支持 SSE4.2（x64v2 可用）"; else bad "CPU 不支持 SSE4.2，请把 KERNEL_ABI 改为 x64v1"; fi
else
    ok "x64v1 兼容所有 x86-64 CPU"
fi

echo "== 5. 网络可达性 =="
check_url() {
    if curl -sSfI -m 12 --retry 1 "$1" >/dev/null 2>&1; then ok "$2"; else warn "$2 不可达：$1"; fi
}
check_url "${DEBIAN_MIRROR}/dists/${DEBIAN_SUITE}/Release" "Debian 镜像 ${DEBIAN_MIRROR}"
check_url "${DEBIAN_SECURITY_MIRROR}/dists/${DEBIAN_SUITE}-security/Release" "安全更新镜像"
check_url "${UKUI_MIRROR}/dists/${UKUI_SUITE}/Release" "UKUI 源（${UKUI_SUITE}）"
check_url "${XANMOD_MIRROR}/dists/${DEBIAN_SUITE}/Release" "XanMod 源"
check_url "${WINEHQ_MIRROR}/dists/${DEBIAN_SUITE}/Release" "WineHQ 源"
check_url "https://api.github.com" "GitHub API（GE-Proton 下载）"

echo
if [[ ${FAIL} -eq 1 ]]; then
    echo "自检未通过，请先修复上面的 FAIL 项。"
    exit 1
fi
echo "自检通过。"
