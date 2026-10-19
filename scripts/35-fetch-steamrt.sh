#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# 抓取 Steam Linux Runtime（umu-launcher / Proton 使用的容器运行时）并内置进 ISO
#
# 下载源：https://repo.steampowered.com/<channel>/images/<version>/
# 归档名规则与 umu 源码一致：steamrt4 -> SteamLinuxRuntime_4.tar.xz
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/build.env
source "${ROOT_DIR}/config/build.env"

DEST="${ROOT_DIR}/build/config/includes.chroot/opt/weos/steam-runtime"

if [[ "${BUNDLE_STEAM_RUNTIME}" != "1" ]]; then
    echo "BUNDLE_STEAM_RUNTIME=0，跳过 Steam 运行时内置"
    exit 0
fi

mkdir -p "${DEST}"

CHANNEL="${STEAMRT_CHANNEL:-steamrt4}"
BASE="https://repo.steampowered.com/${CHANNEL}/images"
CURL_OPTS=(-fsSL --retry 3 --retry-delay 3 --connect-timeout 20)
[[ -n "${STEAMRT_PROXY}" ]] && CURL_OPTS+=(--proxy "${STEAMRT_PROXY}")

echo "== Steam Linux Runtime（${CHANNEL}）=="

if [[ "${STEAMRT_VERSION}" == "latest" ]]; then
    VERSION="$(curl "${CURL_OPTS[@]}" -m 60 "${BASE}/latest-public-beta.txt" | tr -d '\r\n')"
else
    VERSION="${STEAMRT_VERSION}"
fi
[[ -n "${VERSION}" ]] || { echo "[错误] 无法解析运行时版本" >&2; exit 1; }
echo "  版本：${VERSION}"

suffix="${CHANNEL#steamrt}"
if [[ "${suffix}" =~ ^[0-9]+$ ]]; then
    ARCHIVE="SteamLinuxRuntime_${suffix}.tar.xz"
else
    ARCHIVE="SteamLinuxRuntime_${CHANNEL}.tar.xz"
fi
echo "  归档：${ARCHIVE}"

TARGET="${DEST}/${ARCHIVE}"
if [[ -s "${TARGET}" ]]; then
    echo "  已存在，跳过下载"
else
    echo "  下载中（约 165 MB）…"
    curl "${CURL_OPTS[@]}" -m 3600 -o "${TARGET}.part" "${BASE}/${VERSION}/${ARCHIVE}"
    mv "${TARGET}.part" "${TARGET}"
fi

echo "  校验 SHA256"
EXPECTED="$(curl "${CURL_OPTS[@]}" -m 60 "${BASE}/${VERSION}/SHA256SUMS" \
    | grep -E "[ *]${ARCHIVE}\$" | awk '{print $1}' | head -1)"
ACTUAL="$(sha256sum "${TARGET}" | awk '{print $1}')"
if [[ -z "${EXPECTED}" ]]; then
    echo "  [警告] SHA256SUMS 中未找到 ${ARCHIVE}，跳过校验"
elif [[ "${EXPECTED}" != "${ACTUAL}" ]]; then
    echo "  [错误] 校验失败" >&2
    echo "    期望 ${EXPECTED}" >&2
    echo "    实际 ${ACTUAL}" >&2
    rm -f "${TARGET}"
    exit 1
else
    echo "  校验通过：${ACTUAL}"
fi

cat > "${DEST}/VERSION" <<EOF
channel=${CHANNEL}
version=${VERSION}
archive=${ARCHIVE}
sha256=${ACTUAL}
EOF

echo "== 内置运行时就绪 =="
ls -lh "${DEST}"
