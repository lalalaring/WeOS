# 排错手册

## 0. 先看日志

| 场景 | 位置 |
|---|---|
| 构建过程 | `build-logs/weos-<时间戳>.log` |
| lb 详细日志 | `sudo lb build --debug` |
| chroot 内手工验证 | `sudo ./build.sh shell` |
| 安装后系统日志 | `journalctl -b`、`journalctl -b -u lightdm` |
| Calamares 日志 | 安装界面右上角"显示日志"，或 `~/.cache/calamares/` |

## 1. 构建失败

### `apt update` 报 `NO_PUBKEY` / `is not signed`

密钥没进 chroot。检查顺序：

```sh
ls -l build/config/includes.chroot_before_packages/etc/apt/keyrings/
# 必须有 xanmod.gpg、winehq.gpg
sudo ./scripts/10-fetch-keys.sh
```

关键点：密钥必须放 `includes.chroot_before_packages`（装包前注入），
放 `includes.chroot` 就太晚了。

### `E: Unable to locate package ukui-session-manager`

`forky` 源没生效或 pinning 把它压掉了：

```sh
grep -r forky build/config/archives/
cat build/config/includes.chroot_before_packages/etc/apt/preferences.d/00-weos-pinning
```

`forky` 套件名可能随 Debian 发布改名（如 `forky` → `duke`）。用下面命令确认当前名：

```sh
curl -s https://mirrors.tuna.tsinghua.edu.cn/debian/dists/ | grep -oE 'href="[a-z]+/"'
```

### `dpkg: error: cannot remove architecture 'i386' currently in use`

i386 包已装但包列表里没有对应项，通常出现在手工改包列表后。
`lb clean --all` 后重跑 `prepare`。

### `dkms` 编译 NVIDIA 失败

```sh
sudo cat build/chroot/var/lib/dkms/nvidia/*/build/make.log | tail -60
```

对照 `docs/04-nvidia.md` 第 1 节换分支。想先出包：

```sh
# config/build.env
NVIDIA_STRICT="0"
```

### `lb build` 卡在 `Get:` 不动

换成镜像或启用代理：

```sh
# config/build.env
DEBIAN_MIRROR="https://mirrors.ustc.edu.cn/debian"
APT_PROXY="http://127.0.0.1:3142"
```

### 磁盘不足

`lb build` 峰值需要 20 GB 左右（chroot + squashfs + ISO）。
`build/` 与 `dist/` 不要放在 tmpfs 上。

## 2. ISO 启动问题

### 卡在 `Loading ...` 或黑屏

在 GRUB 菜单按 `e` 编辑，把 `quiet splash` 换成 `nosplash debug` 后启动，
看内核输出停在哪。

若提示 `Unable to find a medium containing a live file system`：
ISO 写入方式不对（不要用 Rufus 的 DD 之外的模式，不要解压复制文件）。
Linux 下用：

```sh
sudo dd if=dist/weos-1.0-amd64.iso of=/dev/sdX bs=8M status=progress oflag=sync
```

### `Security Violation` / 直接进固件

Secure Boot 没关。见 `docs/04-nvidia.md` 第 3 节。

### 启动后花屏 / 只有光标

N 卡特有。临时绕过：GRUB 菜单选 `failsafe` 项（已带 `nomodeset`）。
进入系统后按 `docs/04-nvidia.md` 第 5 节排查。

### 无 N 卡机器上黑屏

理论上不会（`weos-gpu-detect` 只在检测到 N 卡时写 xorg.conf）。
若发生：

```sh
sudo rm -f /etc/X11/xorg.conf.d/20-weos-nvidia.conf
sudo systemctl restart lightdm
```

## 3. 桌面问题

### 登录后只有壁纸，没有面板

UKUI 会话启动失败，看：

```sh
journalctl -b --user -u ukui-session 2>/dev/null
ls /usr/share/xsessions/
cat /usr/share/xsessions/ukui.desktop
```

手动启动验证：`ukui-session --replace`。

### 中文显示为方块

```sh
fc-list :lang=zh | head
sudo apt install fonts-noto-cjk
fc-cache -fv
```

### 输入法不出候选词

```sh
im-config -n fcitx5
fcitx5-diagnose
```

常见原因：`GTK_IM_MODULE` 未设置。检查 `/etc/X11/Xsession.d/70weos-im` 是否存在。

### 面板/开始菜单没有图标

`ukui-themes` / `peony-extensions` 未装成功：

```sh
sudo apt install ukui-themes peony-extensions
```

## 4. 安装器问题

### Calamares 打不开

```sh
sudo calamares -d 2>&1 | tail -50
```

常见原因：

- `/etc/calamares/settings.conf` 里 `branding: weos` 但品牌目录缺文件
  → 检查 `/etc/calamares/branding/weos/` 下 5 个文件是否齐全；
- QML 幻灯片报错 → 删除 `branding.desc` 里的 `slideshow: "show.qml"` 一行即可降级。

### 安装到最后 `bootloader` 失败

EFI 分区没挂到 `/boot/efi`，或目标机固件不允许写 NVRAM。
手工补救（chroot 进目标系统）：

```sh
sudo mount /dev/sda2 /mnt && sudo mount /dev/sda1 /mnt/boot/efi
for d in dev proc sys run; do sudo mount --bind /$d /mnt/$d; done
sudo chroot /mnt
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=WeOS
update-grub
```

### 装完重启进不去系统

多为内核与 initramfs 不匹配。用 live ISO 启动后 chroot 修复：

```sh
sudo chroot /mnt
update-initramfs -u -k all
update-grub
```

## 5. 版本与状态核对

```sh
cat /etc/os-release
cat /etc/weos-release
uname -r
weos-gpu-report
wine --version
cat /opt/weos/vendor/VERSIONS
```

## 6. 回滚

构建是幂等的：

```sh
sudo ./build.sh clean      # 删 build/
sudo ./build.sh all        # 从零重建
```

产物保留在 `dist/`，不会因 `clean` 被删。要回到上一个可用镜像，
直接保留旧的 `dist/weos-*.iso` 即可。
