# Wine 与 Proton

## 1. 三个层次的兼容层

| 方案 | 用途 | 位置 |
|---|---|---|
| **WineHQ**（`winehq-devel`） | 运行普通 Windows 软件、开发调试 | `/opt/wine-devel`，命令 `wine` |
| **GE-Proton** | 运行游戏（含 DXVK / VKD3D / 媒体解码补丁） | `/opt/weos/proton/GE-Proton*/` |
| **umu-launcher** | 在 Steam 之外用 Proton 启动游戏（统一前缀管理） | 系统包，命令 `umu-run` |

Steam 内部也使用 Proton：WeOS 已把内置 GE-Proton 链入 Steam 的
`compatibilitytools.d`，在游戏属性 → 兼容性中可直接选择 `GE-Proton11-10`。

## 2. Wine

安装的是 **WineHQ 官方源的最新版**（`winehq-devel`），而非 Debian 自带的 `wine 10.0`。
切换分支只需改 `config/build.env`：

```sh
WINE_FLAVOR="devel"     # devel（最新）| staging（游戏补丁）| stable（稳定）
```

常用命令：

```sh
wine --version                       # 查看版本
weos-wine-tools init                 # 初始化/更新默认前缀 ~/.wine
weos-wine-tools cfg                  # winecfg
weos-wine-tools regedit              # 注册表编辑器
weos-wine-tools tricks vcrun2022     # winetricks 安装运行库
```

多前缀管理（推荐每个应用一个前缀）：

```sh
export WINEPREFIX="$HOME/.local/share/wineprefixes/office"
export WINEARCH=win64
weos-wine-tools init
wine setup.exe
```

已预置的调优项（可在 `~/.wine/user.reg` 覆写）：

- 启用 `wine-mono` / `wine-gecko` 的按需安装；
- `winetricks` 与 `cabextract` 已预装；
- 中文字体由系统 `Noto Sans CJK SC` 提供，Wine 直接复用，无需额外装字体。

## 3. GE-Proton

安装位置：`/opt/weos/proton/GE-Proton11-10/`（版本随构建时最新版变化，
见 `/opt/weos/vendor/VERSIONS`）。

**在 Steam 中使用**：登录后会自动同步（`weos-proton-sync` 由 autostart 触发）。
手动触发：

```sh
weos-proton-sync
```

然后在 Steam → 游戏 → 属性 → 兼容性 → 勾选"强制使用特定 Steam Play 兼容工具"，
选择 `GE-Proton11-10`。

**在 Steam 之外使用**（通过 umu-launcher）：

```sh
# 运行任意 exe
weos-proton-run ~/Games/SomeGame/game.exe

# 指定游戏 ID（决定前缀目录与游戏专用补丁）
GAMEID=umu-12345 weos-proton-run ~/Games/SomeGame/game.exe

# 指定前缀
WINEPREFIX=~/Games/prefixes/somegame weos-proton-run game.exe
```

`weos-proton-run` 实际做的事情：

```sh
export PROTONPATH=/opt/weos/proton/GE-Proton11-10
export GAMEID=${GAMEID:-0}
exec umu-run "$@"
```

**首次运行需要联网**：umu-launcher 会下载 Steam Linux Runtime（sniper）切片到
`~/.local/share/umu/`，约 300 MB，之后可离线使用。

## 4. 游戏叠加层与工具

| 工具 | 命令 | 说明 |
|---|---|---|
| MangoHud | `mangohud %command%` | 帧率/温度/功耗叠加 |
| GOverlay | `goverlay` | MangoHud 图形化配置 |
| Gamescope | `gamescope -W 2560 -H 1440 -f -- %command%` | 微型合成器，支持 FSR / 限帧 |
| GameMode | 自动（`gamemode` 已装） | 游戏时切换 CPU 调度为 performance |
| Lutris | `lutris` | 统一管理 Wine/Proton 游戏与模拟器 |

Steam 启动项示例：

```
gamemoderun mangohud %command%
```

配合 XanMod 内核的 `sched_ext`（`scx_lavd` / `scx_bpfland` 调度器，来自 `scx-scheds`），
游戏负载下的帧时间稳定性会明显好于 CFS 默认调度：

```sh
# 需要内核支持 sched_ext（XanMod 已内置）
sudo apt install scx-scheds
sudo scx_lavd --autopilot      # 或 scx_bpfland
```

## 5. 32 位支持

Steam 与大量老游戏需要 i386 运行时。构建时已在 chroot 内执行
`dpkg --add-architecture i386`，并安装了 `steam-libs-i386`、`wine*-i386`、
`mangohud:i386`。

检查：

```sh
dpkg --print-foreign-architectures     # 应输出 i386
dpkg -l | grep ':i386' | wc -l         # 应有几十个包
```

## 6. 版本核对

```sh
wine --version
umu-run --version
cat /opt/weos/vendor/VERSIONS
ls /opt/weos/proton/
```

`/opt/weos/vendor/VERSIONS` 记录了构建时抓取的 GE-Proton 与 umu-launcher 版本，
便于复现问题。

## 7. 常见问题

**Steam 打不开 / 闪退**

```sh
steam                            # 前台运行看日志
ldd ~/.steam/steam/ubuntu12_32/steam | grep 'not found'
```

多数是缺 32 位库，补装：`sudo apt install libgl1:i386 libglx-mesa0:i386 libvulkan1:i386`。

**游戏提示 "no compatible wine prefix"**
umu 需要 `WINEPREFIX` 可写且未被其他版本占用。删掉重建：

```sh
rm -rf ~/Games/prefixes/somegame
weos-proton-run game.exe
```

**Proton 启动后黑屏但有声音**
多为 DXVK 与驱动不匹配。尝试：

```sh
PROTON_USE_WINED3D=1 weos-proton-run game.exe    # 退回 wined3d
DXVK_HUD=1 weos-proton-run game.exe              # 看 DXVK 是否初始化
```

**中文显示为方块**
Wine 前缀内缺字体。把系统字体链进前缀：

```sh
ln -sf /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc \
       "$WINEPREFIX/drive_c/windows/Fonts/"
```
