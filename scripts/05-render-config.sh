#!/usr/bin/env bash
# 将 os-config 中的 *.in 模板渲染为 live-build 实际读取的文件
# 同时生成 /etc/weos-build.env 供 chroot 钩子读取
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/build.env
source "${ROOT_DIR}/config/build.env"

CFG="${ROOT_DIR}/build/config"
[[ -d "${CFG}" ]] || { echo "配置树不存在：${CFG}" >&2; exit 1; }

# ---------- 派生包名 ----------
KERNEL_META="linux-${KERNEL_BRANCH}-${KERNEL_ABI}"
KERNEL_IMAGE="linux-image-${KERNEL_BRANCH}-${KERNEL_ABI}"
KERNEL_HEADERS="linux-headers-${KERNEL_BRANCH}-${KERNEL_ABI}"

NVIDIA_SUFFIX=""
[[ "${NVIDIA_VARIANT}" == "open" ]] && NVIDIA_SUFFIX="-open"
NVIDIA_DRIVER="nvidia-driver-${NVIDIA_BRANCH}${NVIDIA_SUFFIX}"
NVIDIA_DKMS="nvidia-dkms-${NVIDIA_BRANCH}${NVIDIA_SUFFIX}"

# ---------- 仓库地址 ----------
if [[ "${MIRROR_MODE}" == "snapshot" ]]; then
    XANMOD_URI="http://127.0.0.1:${LOCAL_MIRROR_PORT}/xanmod"
    WINEHQ_URI="http://127.0.0.1:${LOCAL_MIRROR_PORT}/winehq"
else
    XANMOD_URI="${XANMOD_MIRROR%/}"
    WINEHQ_URI="${WINEHQ_MIRROR%/}"
fi

render_file() {
    local src="$1" dst="${1%.in}" tmp
    tmp="$(mktemp)"

    if [[ "$(basename "${src}")" == "debian.list.chroot.in" ]]; then
        case "${DEBIAN_SUITE}" in
            bookworm|trixie) sed 's|^#@STABLE_ONLY@ ||' "${src}" > "${tmp}" ;;
            *)               sed '/@STABLE_ONLY@/d'      "${src}" > "${tmp}" ;;
        esac
    else
        cp "${src}" "${tmp}"
    fi

    sed -i \
        -e "s|@WEOS_NAME@|${WEOS_NAME}|g" \
        -e "s|@WEOS_FULLNAME@|${WEOS_FULLNAME}|g" \
        -e "s|@WEOS_VERSION@|${WEOS_VERSION}|g" \
        -e "s|@WEOS_CODENAME@|${WEOS_CODENAME}|g" \
        -e "s|@WEOS_VENDOR@|${WEOS_VENDOR}|g" \
        -e "s|@DEBIAN_SUITE@|${DEBIAN_SUITE}|g" \
        -e "s|@DEBIAN_MIRROR@|${DEBIAN_MIRROR}|g" \
        -e "s|@DEBIAN_SECURITY_MIRROR@|${DEBIAN_SECURITY_MIRROR}|g" \
        -e "s|@UKUI_SUITE@|${UKUI_SUITE}|g" \
        -e "s|@UKUI_MIRROR@|${UKUI_MIRROR}|g" \
        -e "s|@KERNEL_META@|${KERNEL_META}|g" \
        -e "s|@KERNEL_IMAGE@|${KERNEL_IMAGE}|g" \
        -e "s|@KERNEL_HEADERS@|${KERNEL_HEADERS}|g" \
        -e "s|@NVIDIA_BRANCH@|${NVIDIA_BRANCH}|g" \
        -e "s|@NVIDIA_DRIVER@|${NVIDIA_DRIVER}|g" \
        -e "s|@NVIDIA_DKMS@|${NVIDIA_DKMS}|g" \
        -e "s|@WINE_FLAVOR@|${WINE_FLAVOR}|g" \
        -e "s|@XANMOD_URI@|${XANMOD_URI}|g" \
        -e "s|@WINEHQ_URI@|${WINEHQ_URI}|g" \
        -e "s|@GITHUB_PROXY@|${GITHUB_PROXY}|g" \
        -e "s|@PROTON_VERSION@|${PROTON_VERSION}|g" \
        "${tmp}"

    mv "${tmp}" "${dst}"
    rm -f "${src}"
    echo "  渲染 $(realpath --relative-to="${CFG}" "${dst}")"
}

while IFS= read -r -d '' f; do
    render_file "${f}"
done < <(find "${CFG}" -type f -name '*.in' -print0)

# ---------- 供 chroot 钩子读取的构建环境 ----------
ENV_FILE="${CFG}/includes.chroot_before_packages/etc/weos-build.env"
mkdir -p "$(dirname "${ENV_FILE}")"
cat > "${ENV_FILE}" <<EOF
# 由 scripts/05-render-config.sh 自动生成，请勿手工修改
WEOS_NAME="${WEOS_NAME}"
WEOS_FULLNAME="${WEOS_FULLNAME}"
WEOS_VERSION="${WEOS_VERSION}"
WEOS_CODENAME="${WEOS_CODENAME}"
WEOS_VENDOR="${WEOS_VENDOR}"
DEBIAN_SUITE="${DEBIAN_SUITE}"
DEBIAN_MIRROR="${DEBIAN_MIRROR}"
DEBIAN_SECURITY_MIRROR="${DEBIAN_SECURITY_MIRROR}"
UKUI_SUITE="${UKUI_SUITE}"
UKUI_MIRROR="${UKUI_MIRROR}"
XANMOD_MIRROR="${XANMOD_MIRROR}"
WINEHQ_MIRROR="${WINEHQ_MIRROR}"
XANMOD_URI="${XANMOD_URI}"
WINEHQ_URI="${WINEHQ_URI}"
KERNEL_BRANCH="${KERNEL_BRANCH}"
KERNEL_ABI="${KERNEL_ABI}"
KERNEL_META="${KERNEL_META}"
KERNEL_IMAGE="${KERNEL_IMAGE}"
KERNEL_HEADERS="${KERNEL_HEADERS}"
NVIDIA_BRANCH="${NVIDIA_BRANCH}"
NVIDIA_VARIANT="${NVIDIA_VARIANT}"
NVIDIA_DRIVER="${NVIDIA_DRIVER}"
NVIDIA_DKMS="${NVIDIA_DKMS}"
NVIDIA_STRICT="${NVIDIA_STRICT}"
WINE_FLAVOR="${WINE_FLAVOR}"
PROTON_VERSION="${PROTON_VERSION}"
GITHUB_PROXY="${GITHUB_PROXY}"
EOF

echo "配置渲染完成"
