#!/usr/bin/env bash
# 外部仓库镜像（XanMod / WineHQ 无官方中国镜像，需自建快照）
#
#   ./scripts/20-mirror-external.sh snapshot   抓取完整仓库快照到 LOCAL_MIRROR_DIR
#   ./scripts/20-mirror-external.sh serve      在 127.0.0.1:LOCAL_MIRROR_PORT 提供 HTTP 服务
#   ./scripts/20-mirror-external.sh stop       停止服务
#
# 说明：构建 chroot 与宿主共享网络命名空间，因此 127.0.0.1 可直接访问宿主上的服务。
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/build.env
source "${ROOT_DIR}/config/build.env"

PID_FILE="${ROOT_DIR}/build/.mirror.pid"
ACTION="${1:-snapshot}"

need_debmirror() {
    command -v debmirror >/dev/null 2>&1 || {
        echo "需要 debmirror：apt install debmirror" >&2
        exit 1
    }
}

do_snapshot() {
    need_debmirror
    mkdir -p "${LOCAL_MIRROR_DIR}/xanmod" "${LOCAL_MIRROR_DIR}/winehq"

    echo "== 快照 XanMod（${DEBIAN_SUITE}，main + non-free）=="
    debmirror \
        --arch=amd64 --nosource \
        --method=http --host=deb.xanmod.org --root=/ \
        --dist="${DEBIAN_SUITE}" --section=main,non-free \
        --no-check-gpg --progress \
        "${LOCAL_MIRROR_DIR}/xanmod"

    echo "== 快照 WineHQ（${DEBIAN_SUITE}）=="
    debmirror \
        --arch=amd64 --nosource \
        --method=https --host=dl.winehq.org --root=/wine-builds/debian \
        --dist="${DEBIAN_SUITE}" --section=main \
        --no-check-gpg --progress \
        "${LOCAL_MIRROR_DIR}/winehq"

    du -sh "${LOCAL_MIRROR_DIR}/xanmod" "${LOCAL_MIRROR_DIR}/winehq"
    echo "快照完成。把 config/build.env 的 MIRROR_MODE 设为 snapshot 后重新构建。"
}

do_serve() {
    if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
        echo "镜像服务已在运行（PID $(cat "${PID_FILE}")）"
        return 0
    fi
    mkdir -p "${ROOT_DIR}/build"
    ( cd "${LOCAL_MIRROR_DIR}" && nohup python3 -m http.server "${LOCAL_MIRROR_PORT}" --bind 127.0.0.1 \
        >"${ROOT_DIR}/build/.mirror.log" 2>&1 & echo $! > "${PID_FILE}" )
    sleep 1
    echo "本地镜像服务：http://127.0.0.1:${LOCAL_MIRROR_PORT}（PID $(cat "${PID_FILE}")）"
}

do_stop() {
    if [[ -f "${PID_FILE}" ]]; then
        kill "$(cat "${PID_FILE}")" 2>/dev/null || true
        rm -f "${PID_FILE}"
        echo "镜像服务已停止"
    else
        echo "没有运行中的镜像服务"
    fi
}

case "${ACTION}" in
    snapshot) do_snapshot ;;
    serve)    do_serve ;;
    stop)     do_stop ;;
    *) echo "用法：$0 {snapshot|serve|stop}" >&2; exit 1 ;;
esac
