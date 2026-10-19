#!/usr/bin/env bash
# ============================================================
# WeOS 构建主入口
#
#   ./build.sh check     环境自检
#   ./build.sh prepare   生成 live-build 配置树 + 抓取外部资产
#   ./build.sh build     执行 lb build（约 30-60 分钟）
#   ./build.sh all       check + prepare + build + verify
#   ./build.sh verify    校验 ISO
#   ./build.sh clean     清理构建目录
#   ./build.sh shell     进入 chroot 调试
# ============================================================
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/build.env
source "${ROOT_DIR}/config/build.env"

BUILD_DIR="${ROOT_DIR}/build"
LOG_DIR="${ROOT_DIR}/build-logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/weos-${STAMP}.log"

export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export WEOS_ROOT="${ROOT_DIR}"

c_info() { printf '\033[1;36m[weos]\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m[weos]\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[weos]\033[0m %s\n' "$*" >&2; }
c_err()  { printf '\033[1;31m[weos]\033[0m %s\n' "$*" >&2; }

on_error() {
    local rc=$?
    c_err "构建失败（退出码 ${rc}），日志：${LOG_FILE}"
    c_err "排查建议见 docs/06-troubleshooting.md"
    exit "${rc}"
}
trap on_error ERR

require_root() {
    [[ ${EUID} -eq 0 ]] || { c_err "请使用 root 或 sudo 运行"; exit 1; }
}

cmd_check() {
    bash "${ROOT_DIR}/scripts/00-check-host.sh"
}

cmd_prepare() {
    require_root
    mkdir -p "${BUILD_DIR}" "${LOG_DIR}" "${ROOT_DIR}/${OUTPUT_DIR}"

    c_info "1/5 清理旧配置"
    ( cd "${BUILD_DIR}" && lb clean --all >/dev/null 2>&1 || true )
    rm -rf "${BUILD_DIR:?}/config"

    c_info "2/5 生成 live-build 基础配置（Debian ${DEBIAN_SUITE} / amd64 / hybrid ISO）"
    local apt_proxy_opt=()
    [[ -n "${APT_PROXY}" ]] && apt_proxy_opt=(--apt-http-proxy "${APT_PROXY}")
    local mirror_opts=(
        --mirror-bootstrap "${DEBIAN_MIRROR}"
        --mirror-chroot "${DEBIAN_MIRROR}"
        --mirror-binary "${DEBIAN_MIRROR}"
    )

    (
        cd "${BUILD_DIR}"
        lb config \
            --mode debian \
            --system live \
            --distribution "${DEBIAN_SUITE}" \
            --architectures amd64 \
            --binary-images iso-hybrid \
            --bootloaders "syslinux,grub-efi" \
            --uefi-secure-boot disable \
            --debian-installer false \
            --initsystem systemd \
            --archive-areas "main contrib non-free non-free-firmware" \
            --memtest none \
            --linux-packages none \
            --chroot-squashfs-compression-type xz \
            --bootappend-live "boot=live components quiet splash username=weos hostname=weos locales=zh_CN.UTF-8 keyboard-layouts=us timezone=Asia/Shanghai nvidia-drm.modeset=1" \
            --bootappend-live-failsafe "boot=live components username=weos hostname=weos locales=zh_CN.UTF-8 nvidia-drm.modeset=1 nomodeset" \
            "${mirror_opts[@]}" \
            "${apt_proxy_opt[@]}"
    ) 2>&1 | tee -a "${LOG_FILE}"

    c_info "3/6 复制 WeOS 定制配置树并渲染模板"
    cp -a "${ROOT_DIR}/os-config/." "${BUILD_DIR}/config/"
    bash "${ROOT_DIR}/scripts/05-render-config.sh"
    mkdir -p "${BUILD_DIR}/config/includes.chroot_before_packages/etc/apt/keyrings"
    chmod +x "${BUILD_DIR}"/config/hooks/normal/*.hook.chroot 2>/dev/null || true

    c_info "4/6 导入软件源签名密钥"
    bash "${ROOT_DIR}/scripts/10-fetch-keys.sh"

    c_info "5/6 抓取外部运行时资产（GE-Proton / umu-launcher）"
    bash "${ROOT_DIR}/scripts/30-fetch-runtime.sh"

    c_info "6/6 检查本地镜像快照"
    if [[ "${MIRROR_MODE}" == "snapshot" ]]; then
        [[ -d "${LOCAL_MIRROR_DIR}/xanmod" ]] || {
            c_err "MIRROR_MODE=snapshot 但 ${LOCAL_MIRROR_DIR}/xanmod 不存在，请先执行 scripts/20-mirror-external.sh snapshot"
            exit 1
        }
        c_ok "本地快照就绪"
    else
        c_ok "在线模式，跳过"
    fi

    c_ok "prepare 完成，配置树位于 ${BUILD_DIR}/config"
}

cmd_build() {
    require_root
    [[ -f "${BUILD_DIR}/config/common" ]] || { c_err "配置树不存在，请先执行 ./build.sh prepare"; exit 1; }
    if [[ "${MIRROR_MODE}" == "snapshot" ]]; then
        bash "${ROOT_DIR}/scripts/20-mirror-external.sh" serve
        trap 'bash "${ROOT_DIR}/scripts/20-mirror-external.sh" stop || true' EXIT
    fi

    c_info "开始 lb build（预计 30-60 分钟，取决于网络与 CPU）"
    ( cd "${BUILD_DIR}" && lb build ) 2>&1 | tee -a "${LOG_FILE}"

    local produced
    produced="$(find "${BUILD_DIR}" -maxdepth 1 -name '*.hybrid.iso' -print -quit)"
    [[ -n "${produced}" ]] || { c_err "未找到生成的 ISO"; exit 1; }

    mkdir -p "${ROOT_DIR}/${OUTPUT_DIR}"
    mv "${produced}" "${ROOT_DIR}/${OUTPUT_DIR}/${ISO_BASENAME}.iso"
    ( cd "${ROOT_DIR}/${OUTPUT_DIR}" && sha256sum "${ISO_BASENAME}.iso" > "${ISO_BASENAME}.iso.sha256" )
    c_ok "ISO 已生成：${ROOT_DIR}/${OUTPUT_DIR}/${ISO_BASENAME}.iso"
}

cmd_verify() {
    bash "${ROOT_DIR}/scripts/90-verify-iso.sh"
}

cmd_clean() {
    require_root
    ( cd "${BUILD_DIR}" 2>/dev/null && lb clean --all >/dev/null 2>&1 || true )
    rm -rf "${BUILD_DIR}"
    c_ok "已清理构建目录"
}

cmd_shell() {
    require_root
    ( cd "${BUILD_DIR}" && lb chroot )
}

main() {
    mkdir -p "${LOG_DIR}"
    local action="${1:-all}"
    c_info "WeOS ${WEOS_VERSION} (${WEOS_CODENAME}) / 内核 ${KERNEL_BRANCH}-${KERNEL_ABI} / 日志 ${LOG_FILE}"
    case "${action}" in
        check)   cmd_check ;;
        prepare) cmd_prepare ;;
        build)   cmd_build ;;
        verify)  cmd_verify ;;
        clean)   cmd_clean ;;
        shell)   cmd_shell ;;
        all)     cmd_check; cmd_prepare; cmd_build; cmd_verify ;;
        *)       c_err "未知动作：${action}"; sed -n '2,12p' "$0"; exit 1 ;;
    esac
}

main "$@"
