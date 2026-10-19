# 架构说明

## 1. 分层结构

```
┌──────────────────────────────────────────────────────────────┐
│  应用层   浏览器 / LibreOffice / Steam / Wine / GE-Proton     │
├──────────────────────────────────────────────────────────────┤
│  桌面层   UKUI 4.20  (ukui-session-manager / ukui-panel /     │
│           ukui-control-center / peony / ukwm / ukui-greeter)  │
│           显示栈: Xorg + LightDM                              │
├──────────────────────────────────────────────────────────────┤
│  图形驱动 NVIDIA 专有 595 (nvidia.ko / nvidia-drm / DKMS)     │
│           Mesa (AMD / Intel 兜底) + Vulkan ICD                │
├──────────────────────────────────────────────────────────────┤
│  系统层   Debian 13 trixie (systemd / apt / dpkg / glibc)     │
├──────────────────────────────────────────────────────────────┤
│  内核层   XanMod 7.2.x-x64v3  (BBR3 / sched_ext / le9uo /     │
│           LLVM Polly / Steam Deck EC 驱动)                    │
└──────────────────────────────────────────────────────────────┘
```

## 2. 启动链路

**ISO 引导**

```
UEFI 固件 → /boot/grub/efi.img (grub-efi, 未签名)
BIOS 固件 → isolinux (syslinux)
        ↓
内核 vmlinuz-xanmod-x64v3 + initrd.img（含 live-boot、nvidia 模块）
        ↓
live-boot 挂载 /live/filesystem.squashfs（xz 压缩，只读）
        ↓
live-config 创建 live 用户 weos、设置 hostname/时区/语言、自动登录
        ↓
LightDM + ukui-greeter → UKUI 会话
```

**安装到硬盘后**

```
GRUB (WeOS 主题) → 内核 + initramfs
        ↓
weos-gpu-detect.service（检测到 NVIDIA 卡才写 xorg.conf.d/20-weos-nvidia.conf）
        ↓
LightDM → UKUI 会话
```

`weos-gpu-detect` 的存在是为了让同一份 ISO 既能装在 N 卡机器（走 nvidia 驱动），
也能装在 A 卡/核显机器（走 Mesa），避免无 N 卡时 X 启动失败。

## 3. 软件来源矩阵

| 组件 | 仓库 | 套件 | 组件 | 是否进最终系统 |
|---|---|---|---|---|
| 基础系统 | `mirrors.tuna.tsinghua.edu.cn/debian` | `trixie` | main contrib non-free non-free-firmware | 是 |
| 安全更新 | `mirrors.tuna.tsinghua.edu.cn/debian-security` | `trixie-security` | 同上 | 是 |
| 较新工具 | 同上 | `trixie-backports` | 同上 | 是（优先级 500） |
| UKUI 4.20 | 同上 | `forky` | main | 是（定点 900） |
| 内核 + N 驱动 | `deb.xanmod.org` | `trixie` | main non-free | 是 |
| Wine | `dl.winehq.org/wine-builds/debian` | `trixie` | main | 是 |
| GE-Proton / umu | GitHub Releases | - | - | 是（内置二进制） |

## 4. 运行期关键路径

| 路径 | 内容 |
|---|---|
| `/opt/weos/proton/GE-Proton*/` | 内置 Proton 兼容层 |
| `/opt/weos/steam-runtime/` | 内置 Steam Linux Runtime（steamrt4，约 165 MB） |
| `/usr/local/bin/weos-steamrt-seed` | 把内置运行时释放到当前用户目录 |
| `/opt/weos/vendor/` | 安装包缓存（umu deb 等） |
| `/usr/local/bin/weos-proton-open` | 双击 .exe 的默认处理程序（GE-Proton） |
| `/etc/xdg/mimeapps.list` | 系统级默认关联，把 .exe 绑定到 Proton |
| `/usr/local/bin/weos-proton-run` | 用 Proton 运行任意 exe（命令行） |
| `/usr/local/bin/weos-proton-sync` | 把 GE-Proton 链入 Steam 兼容工具目录 + 写用户级关联 |
| `/usr/local/bin/weos-gpu-report` | 一键输出内核/GPU/驱动状态 |
| `/usr/local/bin/weos-wine-tools` | Wine 常用维护命令 |
| `/etc/weos-release` | 构建信息（内核、驱动、Wine 分支、构建时间） |
| `/etc/weos-build.env` | 构建参数快照（钩子与售后脚本共用） |

## 5. 与 Debian Live 的关系

WeOS 完全复用 Debian Live 的机制（`live-boot` + `live-config` + `lb build`），
没有自研 initramfs 或引导层。这意味着：

- 上游 live-boot 的修复会自动受益；
- ISO 结构、squashfs 布局与官方 Debian Live 一致，便于对照排错；
- 定制点集中在包列表、钩子与文件注入，升级 Debian 版本时改动面小。
