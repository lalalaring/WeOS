# 构建流程

## 1. 阶段总览

```
./build.sh all
 ├─ check    主机自检（Debian 版本 / 工具 / 磁盘 / AVX2 / 镜像连通性）
 ├─ prepare
 │   ├─ lb clean --all            清理旧构建
 │   ├─ lb config ...             生成 live-build 基础配置
 │   ├─ 复制 os-config/ → build/config/
 │   ├─ 05-render-config.sh       渲染 *.in 模板、生成 /etc/weos-build.env
 │   ├─ 10-fetch-keys.sh          导入 XanMod / WineHQ GPG 密钥
 │   ├─ 30-fetch-runtime.sh       抓取 GE-Proton / umu-launcher
 │   ├─ 35-fetch-steamrt.sh       抓取 Steam Linux Runtime（内置，约 165 MB）
 │   └─ 检查本地镜像快照（snapshot 模式）
 ├─ build
 │   ├─ （snapshot 模式）启动本地 HTTP 镜像服务
 │   ├─ lb build                  debootstrap → chroot 定制 → squashfs → ISO
 │   └─ 产物重命名为 dist/weos-1.0-amd64.iso
 └─ verify  校验体积 / SHA256 / 引导扇区 / squashfs / 内核 / efi.img
```

## 2. `lb config` 关键参数

| 参数 | 值 | 原因 |
|---|---|---|
| `--distribution` | `trixie` | Debian 13 稳定版 |
| `--binary-images` | `iso-hybrid` | 同一镜像可 dd 到 U 盘，也可刻盘 |
| `--bootloaders` | `syslinux,grub-efi` | 同时支持 BIOS 与 UEFI |
| `--uefi-secure-boot` | `disable` | XanMod 内核未签名，必须关闭 |
| `--debian-installer` | `false` | 使用 Calamares 而非 d-i |
| `--linux-packages` | `none` | 关闭 live-build 默认内核安装，改用包列表里的 XanMod |
| `--archive-areas` | `main contrib non-free non-free-firmware` | 需要 non-free 的 NVIDIA、contrib 的 Steam |
| `--memtest` | `none` | 精简镜像 |
| `--bootappend-live` | 见下 | live 会话默认参数 |

live 启动参数：

```
boot=live components quiet splash username=weos hostname=weos
locales=zh_CN.UTF-8 keyboard-layouts=us timezone=Asia/Shanghai nvidia-drm.modeset=1
```

## 3. chroot 阶段真实执行顺序

这是 live-build 1:20250505 的实际顺序（`scripts/build/chroot`），定制点必须放对位置：

| 顺序 | 阶段 | 我们的定制 |
|---|---|---|
| 1 | `chroot_prep` | 生成 chroot 的 sources.list（来自 `config/archives/`） |
| 2 | `chroot_linux-image` | 跳过（`--linux-packages none`） |
| 3 | `chroot_firmware` | - |
| 4 | `chroot_preseed` | - |
| 5 | `chroot_includes_before_packages` | `includes.chroot_before_packages/`：GPG 密钥、APT pinning |
| 6 | `chroot_package-lists` + `chroot_install-packages` | `package-lists/*.list.chroot` |
| 7 | `chroot_includes_after_packages` | `includes.chroot/`：品牌、主题、Calamares 品牌、壁纸 |
| 8 | `chroot_hooks` | `hooks/normal/*.hook.chroot`：内核、NVIDIA、UKUI、Wine |
| 9 | `chroot_prep remove` | 清理 chroot 专用源与密钥 |

**关键结论**：GPG 密钥与 pinning 必须在 `includes.chroot_before_packages/`，
否则 `apt update` 时源验签失败；需要 `dpkg --add-architecture` 的操作只能放钩子。

## 4. 钩子职责

| 钩子 | 职责 | 失败影响 |
|---|---|---|
| `0100-system-base` | locale、时区、输入法、skel、服务开关 | 致命 |
| `0200-kernel` | 校验 XanMod 内核与头文件、sysctl 调优、生成 initramfs | 致命 |
| `0300-nvidia` | 安装 NVIDIA 驱动、DKMS 编译、模块参数、GPU 检测服务 | 受 `NVIDIA_STRICT` 控制 |
| `0400-ukui` | 可选组件、LightDM、dconf 默认值、壁纸、会话清理 | 致命 |
| `0500-wine-proton` | i386 多架构、WineHQ、Steam、Lutris、GE-Proton、umu | 非致命降级 |
| `0600-branding` | Plymouth 主题、GRUB 主题、issue | 非致命 |
| `0700-calamares` | 品牌切换、安装器入口 | 非致命 |
| `0900-cleanup` | 最终软件源、清缓存、重置 machine-id | 致命 |

## 5. 模板渲染机制

`os-config` 下所有 `*.in` 文件在 `prepare` 阶段被 `05-render-config.sh` 处理：

- `@WEOS_VERSION@`、`@DEBIAN_SUITE@`、`@KERNEL_IMAGE@`、`@NVIDIA_DRIVER@` 等占位符被替换；
- 渲染后去掉 `.in` 后缀，live-build 才能读到；
- `debian.list.chroot.in` 里 `#@STABLE_ONLY@` 前缀的行，仅在稳定版套件时保留
  （`forky` 没有 `-updates`/`-security` 套件）。

同时生成 `/etc/weos-build.env`，钩子用 `source /etc/weos-build.env` 读取构建参数，
避免在脚本里硬编码版本号。

## 6. 定制点速查

| 想改什么 | 改哪里 |
|---|---|
| 加/减预装软件 | `os-config/package-lists/*.list.chroot.in` |
| 改内核 ABI、驱动分支 | `config/build.env` |
| 改桌面默认值 | `0400-ukui.hook.chroot` 的 dconf 段 |
| 换壁纸 / Logo | 重跑 `scripts/gen-assets.py`，或直接替换 `includes.chroot/usr/share/backgrounds/weos/` |
| 改 GRUB 菜单外观 | `includes.chroot/boot/grub/themes/weos/theme.txt` |
| 改开机动画 | `includes.chroot/usr/share/plymouth/themes/weos/weos.script` |
| 改安装器界面 | `includes.chroot/etc/calamares/branding/weos/` |

## 7. 增量构建

`lb build` 支持断点续跑：失败后修正问题，直接再跑 `sudo ./build.sh build`
（不会重新 debootstrap，除非执行过 `clean`）。调试时可用：

```bash
sudo ./build.sh shell          # 进入 chroot，手工验证命令
sudo lb build --debug          # 详细日志
```

日志在 `build-logs/weos-<时间戳>.log`。
