# 镜像策略（中国大陆优化）

## 1. 为什么不能"全都用国内镜像"

| 仓库 | 国内镜像 | 说明 |
|---|---|---|
| Debian 主源 | ✅ 清华 TUNA / 中科大 USTC / 阿里云 | 完整同步，直连即可 |
| Debian Security | ✅ 同上 | 同上 |
| Debian Backports | ✅ 同上 | 同上 |
| XanMod 内核 | ❌ 无官方中国镜像 | 仅有 `deb.xanmod.org`（IBM Cloud 托管） |
| WineHQ | ❌ 无官方中国镜像 | 仅有 `dl.winehq.org` |
| GitHub（Proton/umu） | ⚠️ 需加速 | 用 `gh-proxy.com` 等前缀代理 |

因此 WeOS 的策略是：**Debian 系全部走清华 TUNA；XanMod/WineHQ 提供"本地快照"模式；
GitHub 资产走加速前缀**。这样既不假装有镜像，也不让构建被外网卡住。

## 2. 默认：在线模式

`config/build.env`：

```sh
DEBIAN_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
DEBIAN_SECURITY_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian-security"
UKUI_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"
MIRROR_MODE="online"
GITHUB_PROXY="https://gh-proxy.com/"
```

此时构建过程：

- debootstrap、apt 全部命中 TUNA（占下载量 90% 以上）；
- XanMod / WineHQ 直连，单个包量不大（内核 + 驱动约 400 MB）；
- GE-Proton / umu 走 `gh-proxy.com` 前缀。

可切换的国内镜像：

```sh
# 中科大
DEBIAN_MIRROR="https://mirrors.ustc.edu.cn/debian"
DEBIAN_SECURITY_MIRROR="https://mirrors.ustc.edu.cn/debian-security"
# 阿里云
DEBIAN_MIRROR="https://mirrors.aliyun.com/debian"
DEBIAN_SECURITY_MIRROR="https://mirrors.aliyun.com/debian-security"
# 华为云
DEBIAN_MIRROR="https://mirrors.huaweicloud.com/debian"
DEBIAN_SECURITY_MIRROR="https://mirrors.huaweicloud.com/debian-security"
```

## 3. 推荐：本地快照模式（可重复、可离线、内网分发）

适用于：需要固定版本的发布构建、多台机器构建、内网无外网出口。

**第一步，抓取快照**（一次性，约 1.5 GB）：

```sh
sudo apt install debmirror
sudo ./scripts/20-mirror-external.sh snapshot
```

它会用 `debmirror` 把 `deb.xanmod.org`（main + non-free）和 `dl.winehq.org`（main）
完整同步到 `/srv/weos-mirror/{xanmod,winehq}`。

**第二步，切换到快照模式**：

```sh
# config/build.env
MIRROR_MODE="snapshot"
LOCAL_MIRROR_DIR="/srv/weos-mirror"
LOCAL_MIRROR_PORT="8399"
```

**第三步，正常构建**：

```sh
sudo ./build.sh prepare
sudo ./build.sh build      # 自动在 127.0.0.1:8399 起 HTTP 服务，构建结束自动停止
```

原理：构建 chroot 与宿主共享网络命名空间，因此 chroot 内访问 `127.0.0.1:8399`
就是宿主上的静态文件服务。`05-render-config.sh` 会把源地址渲染成
`http://127.0.0.1:8399/xanmod` 与 `http://127.0.0.1:8399/winehq`。

> 说明：`snapshot` 模式只影响**构建期**的 chroot 源地址；`0900-cleanup` 写入最终系统时
> 始终使用 `XANMOD_MIRROR` / `WINEHQ_MIRROR` 的上游地址，因此装到真机后仍可正常更新。

## 4. 企业内网：apt-cacher-ng

有多台机器反复构建时，最省事的是缓存代理：

```sh
sudo apt install apt-cacher-ng        # 默认监听 3142
# config/build.env
APT_PROXY="http://10.0.0.5:3142"
```

`build.sh` 会把该值传给 `lb config --apt-http-proxy`，chroot 内所有 apt 请求走缓存。
首次构建后，后续构建几乎不产生外网流量。

## 5. GitHub 资产加速

`GITHUB_PROXY` 支持任意兼容 gh-proxy 的服务（如 `https://gh-proxy.com/`、
`https://ghfast.top/`、自建 `gh-proxy`）。脚本对 API 与 Release 下载同时生效：

```
https://api.github.com/...                → https://gh-proxy.com/https://api.github.com/...
https://github.com/.../GE-Proton11-10.tar.gz → https://gh-proxy.com/https://github.com/...
```

留空 `GITHUB_PROXY=""` 即直连。

若代理不可用，也可手工下载后放入 `build/config/includes.chroot/opt/weos/vendor/`，
命名保持 `GE-Proton11-10-x86_64.tar.gz` 与 `python3-umu-launcher_1.4.4-1_amd64_debian-13.deb`，
脚本检测到已存在会跳过下载。

## 6. 最终系统的软件源

`0900-cleanup` 写入的内容：

`/etc/apt/sources.list`

```
deb https://mirrors.tuna.tsinghua.edu.cn/debian trixie main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian trixie-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian trixie-backports main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security trixie-security main contrib non-free non-free-firmware
```

`/etc/apt/sources.list.d/weos-thirdparty.list`

```
deb [signed-by=/etc/apt/keyrings/xanmod.gpg] http://deb.xanmod.org trixie main non-free
deb [signed-by=/etc/apt/keyrings/winehq.gpg] https://dl.winehq.org/wine-builds/debian trixie main
deb https://mirrors.tuna.tsinghua.edu.cn/debian forky main
```

用户可以用一条命令关掉全部第三方源（排查问题时很有用）：

```sh
sudo mv /etc/apt/sources.list.d/weos-thirdparty.list{,.disabled}
sudo apt update
```

## 7. 完全离线构建

```sh
# 有网机器
sudo ./scripts/20-mirror-external.sh snapshot
sudo ./build.sh prepare            # 抓取 GE-Proton / umu
tar czf weos-offline.tar.gz /srv/weos-mirror build/config/includes.chroot/opt/weos/vendor

# 离线机器
tar xzf weos-offline.tar.gz -C /
# 再用 MIRROR_MODE=snapshot 构建
```

Debian 主源本身也可以先用 `debmirror` 或 `apt-mirror` 做内网镜像，
把 `DEBIAN_MIRROR` 指向内网地址即可，其余不变。
