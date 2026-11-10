# HiSilicon DLC

适用于 Debian 12/13 arm64、systemd 和支持 HiVXE 的海思内核。FFmpeg/FFprobe 及私有库以 Debian 12 的 glibc 2.36 为构建基线，两套系统共用同一套产物。使用 root 执行：

```sh
curl -fL https://raw.githubusercontent.com/HiSilicon-Development/extra/main/install.sh -o install.sh
bash install.sh                  # 默认安装全部，使用上游适配版 OSCam
# bash install.sh --oscam-nx111  # 改用 nx111 版 OSCam
```

如遇网络不好，首次下载可用 `https://gh-proxy.org/https://raw.githubusercontent.com/HiSilicon-Development/extra/main/install.sh`。

脚本会自动识别，为 GitHub 程序及私有依赖下载加上 `https://gh-proxy.org/` 前缀；apt 依赖使用系统现有软件源。

安装内容：

- `/usr/local/bin/hivxe-ffmpeg`、`hivxe-ffprobe` 及 `/usr/local/lib/hivxe-ffmpeg/` 私有库；`libc6`、`libdrm2`、`libudev1`、`ca-certificates`、`curl`、`tar`、`gzip`、`coreutils` 等系统运行库由 apt 安装。
- 编解码硬件监控 `hivxe-top`，以及转码脚本 `hivxe-transcode`（MPEG-TS 标准输入/输出）。
- `/usr/local/bin/oscam`、`/usr/local/etc/oscam.*` 配置和自动启动的 `oscam.service`。

全新安装的 OSCam WebUI：`http://设备IP:8888`，账号/密码均为 `oscam`，请自行修改。

检测到已有 OSCam 时，交互选择是否先备份（默认备份）。

备份保存为 `/root/OSCam_backup_YYYY-MM-DD-HH:MM.tar.gz`，包含旧程序、`oscam.*` 配置和 service；无论是否备份，随后都会覆盖 OSCam 程序和随包提供的默认配置。

相同分钟的备份文件已存在时会停止，不覆盖旧备份。

HiVXE 程序和私有依赖直接覆盖更新，不备份。

运行 `hivxe-top` 在终端独立屏幕中每秒刷新，`Ctrl+C` 退出后恢复原终端。

`hivxe-top --once` 输出一次，适用于管道或日志。

在仓库根目录运行 `sha256sum --check --strict SHA256SUMS` 可校验全部随包文件。
更新 FFmpeg/FFprobe 或私有库时，须同时将 `SHA256SUMS` 中对应条目更新为新文件的实际摘要；安装脚本会严格检查这些摘要。
