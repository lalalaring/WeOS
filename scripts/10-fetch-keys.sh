#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# 下载并安装第三方仓库签名密钥到构建树的 keyrings 目录
# 产物：build/config/includes.chroot_before_packages/etc/apt/keyrings/{xanmod,winehq}.gpg
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/build.env
source "${ROOT_DIR}/config/build.env"

KEYRING_DIR="${ROOT_DIR}/build/config/includes.chroot_before_packages/etc/apt/keyrings"
mkdir -p "${KEYRING_DIR}"

fetch_key() {
    local name="$1" url="$2" out="${KEYRING_DIR}/$1.gpg"
    if [[ -s "${out}" ]]; then
        echo "  已存在 ${name}.gpg，跳过"
        return 0
    fi
    local tmp
    tmp="$(mktemp)"
    echo "  下载 ${name} 密钥：${url}"
    if ! curl -fsSL --retry 3 --retry-delay 2 -m 60 -o "${tmp}" "${url}"; then
        echo "  [错误] 无法下载 ${url}" >&2
        echo "  可手动下载后执行： gpg --dearmor -o ${out} < 密钥文件" >&2
        rm -f "${tmp}"
        return 1
    fi
    gpg --batch --yes --dearmor -o "${out}" < "${tmp}"
    rm -f "${tmp}"
    chmod 0644 "${out}"
    echo "  [完成] ${out}"
}

echo "== 导入仓库密钥 =="
fetch_key xanmod "https://dl.xanmod.org/archive.key"
fetch_key winehq "https://dl.winehq.org/wine-builds/winehq.key"

ls -l "${KEYRING_DIR}"
