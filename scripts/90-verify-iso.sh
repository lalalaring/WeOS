#!/usr/bin/env bash
# ISO 产物校验
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/build.env
source "${ROOT_DIR}/config/build.env"

ISO="${ROOT_DIR}/${OUTPUT_DIR}/${ISO_BASENAME}.iso"
FAIL=0
ok()  { printf '  [ OK ] %s\n' "$*"; }
bad() { printf '  [FAIL] %s\n' "$*"; FAIL=1; }

echo "== ISO 校验：${ISO} =="
[[ -f "${ISO}" ]] || { echo "文件不存在"; exit 1; }

size_mb=$(( $(stat -c %s "${ISO}") / 1024 / 1024 ))
if [[ ${size_mb} -ge 2048 ]]; then ok "体积 ${size_mb} MB"; else bad "体积异常（${size_mb} MB）"; fi

if [[ -f "${ISO}.sha256" ]]; then
    ( cd "$(dirname "${ISO}")" && sha256sum -c "$(basename "${ISO}").sha256" ) && ok "SHA256 匹配" || bad "SHA256 不匹配"
else
    ( cd "$(dirname "${ISO}")" && sha256sum "$(basename "${ISO}")" > "$(basename "${ISO}").sha256" )
    ok "已生成 SHA256"
fi

if file "${ISO}" | grep -qi 'ISO 9660'; then ok "ISO9660 文件系统"; else bad "不是合法 ISO"; fi
if file "${ISO}" | grep -qi 'boot sector'; then ok "含引导扇区（BIOS 可引导）"; else bad "缺少引导扇区"; fi

if command -v xorriso >/dev/null 2>&1; then
    iso_ls() { xorriso -indev "${ISO}" -ls "$1" 2>/dev/null; }
    echo "== 引导与根文件系统 =="
    iso_ls /live/ | grep -q 'squashfs' \
        && ok "找到 squashfs 根文件系统" || bad "未找到 squashfs"
    iso_ls /live/ | grep -q 'vmlinuz' \
        && ok "找到 XanMod 内核" || bad "未找到内核"
    iso_ls /live/ | grep -q 'initrd' \
        && ok "找到 initramfs" || bad "未找到 initramfs"
    iso_ls /boot/grub/ | grep -q 'efi.img' \
        && ok "找到 UEFI 引导镜像" || bad "未找到 UEFI 引导镜像"
    echo
    echo "== /live 目录 =="
    iso_ls /live/
fi

echo
if [[ ${FAIL} -eq 1 ]]; then echo "校验未通过"; exit 1; fi
echo "校验通过。写入 U 盘："
echo "  sudo dd if=${ISO} of=/dev/sdX bs=8M status=progress oflag=sync"
