# NVIDIA 专有驱动方案

## 1. 为什么用 XanMod 的 non-free 仓库

XanMod 内核用 LLVM/Clang 构建，启用了 `CONFIG_LTO_CLANG` 等选项。
Debian 官方 `nvidia-driver` 的 DKMS 源码在较新内核上经常编译失败
（典型报错：`error: implicit declaration of function 'vm_flags_...'`、
`Unknown symbol` 等）。XanMod 在其 `non-free` 组件里提供了**已适配自身内核的驱动包**：

| 包名 | 含义 |
|---|---|
| `nvidia-driver-595` | 生产分支（Proprietary），595.104.02 |
| `nvidia-driver-595-open` | 同版本，开源内核模块 |
| `nvidia-dkms-595` | DKMS 源码包，编译期生成 `nvidia.ko` |
| `nvidia-kernel-common-595` | 公共脚本（`nvidia-persistenced` 等） |

可选分支：`580`（旧卡兼容）、`590`、`595`（默认）、`610`、`615`（新特性分支）。

在 `config/build.env` 中切换：

```sh
NVIDIA_BRANCH="595"
NVIDIA_VARIANT="proprietary"   # 或 open
```

## 2. 构建期发生了什么

`0300-nvidia.hook.chroot` 按以下顺序执行：

1. `apt-get install nvidia-driver-595 nvidia-dkms-595`
2. `dkms autoinstall -k <xanmod 内核版本>` 显式针对 ISO 内核编译
3. 校验 `/lib/modules/<ver>/updates/dkms/nvidia.ko*` 是否存在
4. 写模块参数 `/etc/modprobe.d/weos-nvidia.conf`
5. 把 `nvidia nvidia_modeset nvidia_uvm nvidia_drm` 加入 initramfs
6. `update-initramfs -u -k <ver>`
7. 启用 `nvidia-persistenced`、`nvidia-suspend/resume/hibernate`
8. 安装 `weos-gpu-detect` 服务（只在有 N 卡时启用 Xorg 的 nvidia 驱动）

因为 ISO 内模块是为**同一个内核版本**编译的，所以 live 启动时可直接加载，无需现场编译。
装到硬盘后若升级内核，DKMS 会在 `apt upgrade` 时自动重新编译。

失败行为由 `NVIDIA_STRICT` 控制：

- `1`（默认）：编译失败即终止构建，避免发出"号称带 N 驱动但实际没有"的镜像；
- `0`：打印警告并以 nouveau 继续出包，适合先跑通流程。

## 3. Secure Boot

**必须关闭 Secure Boot**。原因：XanMod 内核没有微软签名，`shim` 会拒绝加载，
表现为开机直接进入固件界面或提示 `Security Violation`。

BIOS 中关闭项通常叫：`Secure Boot` → `Disabled`。
若必须开启，需要自行完成 MOK 流程（本套件未内置）：

```sh
# 在目标机上（示例，需自备签名密钥）
sudo apt install sbsigntool
sudo sbsign --key MOK.key --cert MOK.crt \
     --output /boot/vmlinuz-$(uname -r).signed /boot/vmlinuz-$(uname -r)
sudo mokutil --import MOK.crt
```

同时 NVIDIA 模块也需要签名（`/etc/dkms/framework.conf` 里配置 `mok_signing_key`）。

## 4. 验证

在 live 会话或装好的系统里：

```sh
weos-gpu-report
```

输出示例：

```
== 内核 ==
7.2.11-x64v3-xanmod1
== GPU ==
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD104 [GeForce RTX 4070] [10de:2786]
== 驱动模块 ==
nvidia 67108864 120 nvidia_uvm,nvidia_modeset
== DKMS ==
nvidia/595.104.02, 7.2.11-x64v3-xanmod1, x86_64: installed
== nvidia-smi ==
| NVIDIA-SMI 595.104.02   Driver Version: 595.104.02   CUDA Version: 13.x |
```

其它常用检查：

```sh
cat /proc/driver/nvidia/version
lsmod | grep nvidia
glxinfo -B | grep -E 'OpenGL renderer|OpenGL version'
vulkaninfo --summary | head -20
```

## 5. 常见问题

**黑屏 / 停在光标**
多为 nvidia 模块未加载或 Xorg 配置错误。切到 tty（`Ctrl+Alt+F2`）后：

```sh
journalctl -b -u lightdm
dmesg | grep -i nvidia
weos-gpu-report
sudo rm -f /etc/X11/xorg.conf.d/20-weos-nvidia.conf   # 让 X 自动探测
sudo systemctl restart lightdm
```

**`nvidia-smi` 报 "Failed to initialize NVML: Driver/library version mismatch"**
内核模块与用户态库版本不一致，通常是内核升级后模块没重编：

```sh
sudo dkms autoinstall
sudo update-initramfs -u -k all
sudo reboot
```

**DKMS 编译失败**
看日志：

```sh
sudo cat /var/lib/dkms/nvidia/*/build/make.log | tail -50
```

若内核过新，把 `NVIDIA_BRANCH` 换成更新的分支（如 `615`）或改用 `NVIDIA_VARIANT="open"`。

**多显卡 / Optimus 笔记本**
`nvidia-prime` 已安装，可用 `prime-select` 切换（如可用）：

```sh
prime-select query
prime-select nvidia
```

UKUI 基于 X11，`prime-select` 切换后需要注销重新登录。

**睡眠唤醒后花屏**
已默认设置 `NVreg_PreserveVideoMemoryAllocations=1` 并启用
`nvidia-suspend/resume/hibernate` 服务。若仍异常，检查：

```sh
systemctl status nvidia-suspend.service
cat /proc/driver/nvidia/params | grep PreserveVideoMemoryAllocations
```
