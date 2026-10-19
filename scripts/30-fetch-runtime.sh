#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# 抓取外部运行时资产到构建树（离线内置进 ISO）
#   - GE-Proton（Proton 兼容层，x86_64）
#   - umu-launcher（Steam 之外的 Proton 启动器，Debian 13 原生 deb）
# 产物：build/config/includes.chroot/opt/weos/vendor/
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/build.env
source "${ROOT_DIR}/config/build.env"

VENDOR_DIR="${ROOT_DIR}/build/config/includes.chroot/opt/weos/vendor"
mkdir -p "${VENDOR_DIR}"

proxy() {
    if [[ -n "${GITHUB_PROXY}" ]]; then printf '%s%s' "${GITHUB_PROXY%/}/" "$1"; else printf '%s' "$1"; fi
}

download() {
    local url="$1" out="$2"
    if [[ -s "${out}" ]]; then echo "  已存在 $(basename "${out}")，跳过"; return 0; fi
    echo "  下载 $(basename "${out}")"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -m 1800 -o "${out}.part" "$(proxy "${url}")" \
        || { echo "  [失败] ${url}" >&2; rm -f "${out}.part"; return 1; }
    mv "${out}.part" "${out}"
}

echo "== 解析 GE-Proton 版本 =="
if [[ "${PROTON_VERSION}" == "latest" ]]; then
    GE_TAG="$(curl -fsSL -m 60 "$(proxy "https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest")" \
        | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"
    [[ -n "${GE_TAG}" ]] || { echo "[错误] 无法解析 GE-Proton 最新版本，请在 build.env 中写死 PROTON_VERSION" >&2; exit 1; }
else
    GE_TAG="${PROTON_VERSION}"
fi
echo "  GE-Proton 版本：${GE_TAG}"

GE_ASSET="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_TAG}/${GE_TAG}-x86_64.tar.gz"
GE_SUM="${GE_ASSET}.sha512sum"
download "${GE_ASSET}" "${VENDOR_DIR}/${GE_TAG}-x86_64.tar.gz"
download "${GE_SUM}"   "${VENDOR_DIR}/${GE_TAG}-x86_64.tar.gz.sha512sum" || true

if [[ -s "${VENDOR_DIR}/${GE_TAG}-x86_64.tar.gz.sha512sum" ]]; then
    ( cd "${VENDOR_DIR}" && sha512sum -c "${GE_TAG}-x86_64.tar.gz.sha512sum" ) \
        || { echo "[错误] GE-Proton 校验失败" >&2; exit 1; }
    echo "  GE-Proton 校验通过"
fi

echo "== 解析 umu-launcher 版本 =="
UMU_TAG="$(curl -fsSL -m 60 "$(proxy "https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest")" \
    | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)"
UMU_DEB="python3-umu-launcher_${UMU_TAG}-1_amd64_debian-13.deb"
UMU_URL="https://github.com/Open-Wine-Components/umu-launcher/releases/download/${UMU_TAG}/${UMU_DEB}"
echo "  umu-launcher 版本：${UMU_TAG}"
download "${UMU_URL}" "${VENDOR_DIR}/${UMU_DEB}"

cat > "${VENDOR_DIR}/VERSIONS" <<EOF
GE_PROTON=${GE_TAG}
UMU_LAUNCHER=${UMU_TAG}
FETCHED_AT=$(date -Iseconds)
EOF

echo "== 资产清单 =="
ls -lh "${VENDOR_DIR}"
