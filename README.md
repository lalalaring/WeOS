# WeOS

基于 **XanMod 内核 + Debian 工具链 + UKUI 桌面** 的桌面 Linux 发行版构建套件。
面向中文用户与游戏场景：内置 NVIDIA 专有驱动、最新版 Wine、GE-Proton 与 umu-launcher，
全流程使用中国镜像拉取。

构建产物为可直接写入 U 盘启动的混合 ISO（BIOS + UEFI），并附带 Calamares 图形安装器。

---

## 1. 技术栈

| 层次 | 选型 | 版本（2026-10） | 来源 |
|---|---|---|---|
| 基础系统 | Debian 13 `trixie` | 13.x | 清华 TUNA |
| 构建工具链 | live-build + debootstrap + dpkg/apt | 1:20250505+deb13u1 | Debian |
| 内核 | XanMod（`x64v3` ABI） | 7.2.11-xanmod1 | deb.xanmod.org |
| 桌面环境 | UKUI | 4.20.x / 4.22.x | Debian `forky` |
| 显示管理器 | LightDM + ukui-greeter | 1.32 | Debian |
| 显卡驱动 | NVIDIA 专有（DKMS） | 595.104.02 | XanMod `non-free` |
| Wine | WineHQ `devel` | 最新 | dl.winehq.org |
| Proton | GE-Proton | 11-10 | GitHub |
| Proton 启动器 | umu-launcher | 1.4.4 | GitHub（Debian 13 原生 deb） |
| 安装器 | Calamares | 3.3.14 | Debian |

内核 ABI 说明：`x64v3` 需要 2015 年后的 CPU（Haswell / Zen 及以上）。
老机器请把 `config/build.env` 中的 `KERNEL_ABI` 改为 `x64v2` 或 `x64v1`。

**开箱即用的 Proton**：双击任意 `.exe` 默认就用内置 GE-Proton 运行（不经过 Wine、
不需要开终端），每个游戏目录自动分配独立前缀。详见 [docs/05-wine-proton.md](docs/05-wine-proton.md)。

---

## 2. 三个关键设计决策

**① UKUI 从 Debian `forky` 定点取包，而不是整机用 testing**

Debian 13 `trixie` 只收录了部分 UKUI 组件（缺 `ukui-session-manager`、`ukui-panel`、
`ukui-control-center`、`ukui-media`、`ukui-power-manager`、`ukui-greeter`），
无法组成可用桌面；完整 UKUI 4.20 只存在于 `forky`/`sid`。
因此采用 **APT pinning 定点提升**：`trixie` 优先级 990，`forky` 整体 100，
仅 `ukui-*` / `peony*` / `ukwm*` 提升到 900。系统主体仍是稳定版，只有桌面组件来自 testing。
策略文件见 `os-config/includes.chroot_before_packages/etc/apt/preferences.d/00-weos-pinning.in`。

**② NVIDIA 驱动取自 XanMod 自己的 non-free 仓库**

XanMod 用 LLVM 构建内核，Debian 官方 `nvidia-driver` 的 DKMS 在 7.x 内核上经常编译失败。
XanMod 提供了针对其内核验证过的 `nvidia-driver-595` / `nvidia-dkms-595`（以及 `-open` 变体），
ABI 匹配、开箱可编译。Secure Boot 必须关闭（XanMod 内核未签名）。

**③ Steam / Wine / Lutris 在 chroot 钩子里安装，而不是放进包列表**

它们依赖 i386 多架构（32 位 Steam 运行时、Wine 的 wow64 组件），
而 live-build 的包列表阶段无法执行 `dpkg --add-architecture i386`。
所以这部分放在 `0500-wine-proton.hook.chroot`：先加 i386、再 `apt update`、再安装，
顺序可控，失败也能优雅降级。

---

## 3. 目录结构

```
WeOS/
├── build.sh                    # 主入口：check / prepare / build / verify / clean / shell
├── Makefile                    # make all 等目标
├── config/build.env            # 唯一配置入口（版本、镜像、内核 ABI、驱动分支…）
├── os-config/                  # live-build 配置源（会被渲染后复制到 build/config）
│   ├── archives/               # 软件源（*.list.chroot.in 模板）
│   ├── package-lists/          # 包列表（00-base … 50-installer）
│   ├── hooks/normal/           # chroot 钩子（0100 基础 … 0900 清理）
│   └── includes.chroot*/       # 文件注入（品牌、主题、源优先级、Calamares 品牌）
├── scripts/
│   ├── 00-check-host.sh        # 构建主机自检
│   ├── 05-render-config.sh     # 模板渲染 + 生成 /etc/weos-build.env
│   ├── 10-fetch-keys.sh        # 导入 XanMod / WineHQ 签名密钥
│   ├── 20-mirror-external.sh   # XanMod / WineHQ 本地快照与 HTTP 服务
│   ├── 30-fetch-runtime.sh     # 抓取 GE-Proton / umu-launcher
│   ├── 90-verify-iso.sh        # 产物校验
│   └── gen-assets.py           # 生成壁纸 / Logo（纯标准库）
├── docs/                       # 架构、构建、镜像、NVIDIA、Wine/Proton、排错
├── build/                      # 构建工作目录（生成，勿手工编辑）
└── dist/                       # 产物 ISO
```

---

## 4. 快速开始

构建主机要求：**Debian 13（或 Debian 容器）、root、25 GB 可用空间、x86-64 且支持 AVX2**。

```bash
# 1) 安装构建依赖
sudo apt install live-build debootstrap xorriso squashfs-tools rsync gnupg curl \
                 xz-utils debmirror python3

# 2) 自检（会检查镜像连通性、磁盘、CPU 指令集）
sudo ./build.sh check

# 3) 一键构建（生成配置 → 抓取资产 → lb build → 校验）
sudo ./build.sh all
```

分步执行：

```bash
sudo ./build.sh prepare     # 只生成配置树、抓取资产，不编译
sudo ./build.sh build       # 只跑 lb build
sudo ./build.sh verify      # 只校验已有 ISO
sudo ./build.sh clean       # 清理 build/
```

产物：

```
dist/weos-1.0-amd64.iso
dist/weos-1.0-amd64.iso.sha256
```

写盘：

```bash
sudo dd if=dist/weos-1.0-amd64.iso of=/dev/sdX bs=8M status=progress oflag=sync
```

首次构建约 30-60 分钟（取决于网络与 CPU），镜像约 5-7 GB。

---

## 5. 常用配置变更

全部集中在 `config/build.env`，改完重跑 `./build.sh prepare && ./build.sh build`：

| 变量 | 作用 | 常见取值 |
|---|---|---|
| `KERNEL_ABI` | 内核微架构等级 | `x64v1` / `x64v2` / `x64v3` |
| `KERNEL_BRANCH` | 内核分支 | `xanmod` / `xanmod-lts` / `xanmod-edge` |
| `NVIDIA_BRANCH` | 驱动分支 | `580` / `590` / `595` / `610` / `615` |
| `NVIDIA_VARIANT` | 模块类型 | `proprietary` / `open` |
| `WINE_FLAVOR` | Wine 分支 | `devel` / `staging` / `stable` |
| `DEBIAN_SUITE` | 基础系统 | `trixie`（稳定）/ `forky`（滚动） |
| `MIRROR_MODE` | 镜像策略 | `online` / `snapshot` |

---

## 6. 文档

| 文档 | 内容 |
|---|---|
| [docs/01-architecture.md](docs/01-architecture.md) | 分层架构、启动链路、包来源矩阵 |
| [docs/02-build.md](docs/02-build.md) | 构建流程逐步拆解、钩子顺序、定制点 |
| [docs/03-mirrors.md](docs/03-mirrors.md) | 中国镜像策略、内网镜像、离线构建 |
| [docs/04-nvidia.md](docs/04-nvidia.md) | 驱动方案、Secure Boot、DKMS 排错 |
| [docs/05-wine-proton.md](docs/05-wine-proton.md) | Wine / GE-Proton / umu 用法与调优 |
| [docs/06-troubleshooting.md](docs/06-troubleshooting.md) | 常见故障与定位方法 |

---

## 7. 参与开发

仓库已初始化，主分支 `main`，首次提交为完整构建套件。

```bash
git status                 # 工作区应为干净
git log --oneline          # 查看提交历史
```

改动约定：

- 只改 `config/build.env` 的，提交信息写 `chore(config): ...`
- 改包列表 / 钩子 / 源的，写 `feat(os-config): ...` 或 `fix(os-config): ...`
- 文档改动写 `docs: ...`
- 提交前请确保 `bash -n` 通过：

```bash
for f in build.sh scripts/*.sh os-config/hooks/normal/*.hook.chroot; do bash -n "$f" || echo "FAIL $f"; done
```

`.gitattributes` 已强制 LF 换行，脚本在索引中标记为 `100755`，
因此克隆到 Linux 后可直接执行，无需额外 `chmod`。
`build/`、`dist/`、`build-logs/` 与抓取的外部资产均已忽略。

本项目以 **GPL-2.0** 发布，详见 [LICENSE](LICENSE)。

---

## 8. 已知限制

- **Secure Boot 必须关闭**：XanMod 内核未签名。后续可接入自签名 MOK 流程。
- **UKUI 来自 testing**：个别依赖可能随 `forky` 变动而短暂不可满足，届时把 `DEBIAN_SUITE`
  切到 `forky` 全量滚动即可绕过。
- **NVIDIA 驱动为 ISO 内预编译**：升级内核后需重新 `dkms autoinstall`（已配置自动触发）。
- **umu-launcher 首次运行需联网**下载 Steam Runtime 切片。
- 未内置 Flatpak / Snap；未做 ARM64 适配。

---

## 9. 许可证

本项目（构建脚本、配置模板、文档、品牌资源）以 **GNU General Public License v2.0**
发布，全文见 [LICENSE](LICENSE)。

SPDX 标识符：`GPL-2.0-only`

需要说明的边界：

- WeOS 产出的 ISO 中**包含**第三方软件（Debian 软件包、XanMod 内核、NVIDIA 专有驱动、
  Wine、GE-Proton 等），它们各自遵循原有许可证。其中 NVIDIA 驱动为闭源专有许可，
  再分发需遵守 NVIDIA 的许可条款。
- GPL-2.0 覆盖的是本仓库的构建逻辑与定制文件，不改变上述上游组件的授权。
- 若你在此基础上二次分发 ISO，请自行确认各上游组件的再分发条件。
