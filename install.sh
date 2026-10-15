#!/bin/bash
set -euo pipefail

REPOSITORY=https://github.com/HiSilicon-Development/extra
PROXY=https://gh-proxy.org/
OSCAM_VARIANT=upstream

usage() {
    cat <<'EOF'
用法: sudo bash install.sh [--oscam-nx111]

安装 HiVXE FFmpeg/FFprobe、hivxe-top、hivxe-transcode 和 OSCam。
默认使用已编译的上游适配版 OSCam；--oscam-nx111 改用 nx111。
适用于 Debian 12 arm64、systemd 和支持 HiVXE 的海思内核。
EOF
}

for option in "$@"; do
    case "$option" in
        --oscam-nx111) OSCAM_VARIANT=nx111 ;;
        -h|--help) usage; exit 0 ;;
        *) printf '未知参数: %s\n' "$option" >&2; usage >&2; exit 2 ;;
    esac
done

fail() { printf '错误: %s\n' "$*" >&2; exit 1; }
section() {
    printf '\n================================================================\n'
    printf '%s\n' "$*"
    printf '================================================================\n'
}
[[ $EUID == 0 ]] || fail '请使用 root 或 sudo 运行。'
[[ $(uname -m) == aarch64 && $(dpkg --print-architecture) == arm64 ]] ||
    fail '预编译程序仅适用于 arm64/aarch64。'
[[ -r /etc/os-release ]] || fail '无法识别系统。'
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 12 ]] ||
    fail '此安装包使用 Debian 12 arm64 的运行库。'
command -v apt-get >/dev/null || fail '未找到 apt-get。'
command -v systemctl >/dev/null && [[ -d /run/systemd/system ]] ||
    fail '请在运行 systemd 的系统上安装。'

TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

# Only normal Debian runtime packages come from apt. Private FFmpeg libraries
# are delivered with the GitHub payload, never substituted with Debian FFmpeg.
export DEBIAN_FRONTEND=noninteractive
section '安装系统依赖'
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl tar gzip \
    coreutils libc6 libdrm2 libudev1

section '获取安装文件'
DOWNLOAD_PREFIX=
TRACE=$(curl -fsS --connect-timeout 5 --max-time 10 \
    https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)
if [[ $'\n'${TRACE}$'\n' == *$'\nloc=CN\n'* ]]; then
    DOWNLOAD_PREFIX=$PROXY
elif [[ $'\n'${TRACE}$'\n' != *$'\nloc='* ]]; then
    COUNTRY=$(curl -fsS --connect-timeout 5 --max-time 10 \
        https://ipinfo.io/country 2>/dev/null || true)
    [[ $COUNTRY != CN ]] || DOWNLOAD_PREFIX=$PROXY
fi
if [[ -n $DOWNLOAD_PREFIX ]]; then
    printf '检测到国内网络，GitHub 程序和私有依赖使用 %s\n' "$PROXY"
else
    printf '使用 GitHub 原始下载地址。\n'
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ -d $SCRIPT_DIR/payload && -f $SCRIPT_DIR/SHA256SUMS ]]; then
    PACKAGE_DIR=$SCRIPT_DIR
else
    PACKAGE_DIR=$TEMP_DIR/package
    mkdir -p "$PACKAGE_DIR"
    ARCHIVE_URL=$REPOSITORY/archive/refs/heads/main.tar.gz
    curl -fL --connect-timeout 10 --max-time 300 \
        "${DOWNLOAD_PREFIX}${ARCHIVE_URL}" -o "$TEMP_DIR/extra.tar.gz"
    tar -xzf "$TEMP_DIR/extra.tar.gz" --strip-components=1 -C "$PACKAGE_DIR"
fi
section '校验安装文件'
(
    cd "$PACKAGE_DIR"
    sha256sum --check --strict SHA256SUMS
)
PAYLOAD=$PACKAGE_DIR/payload
[[ -x $PAYLOAD/oscam/$OSCAM_VARIANT/oscam ]] || fail '缺少所选 OSCam 二进制。'

# Only OSCam needs an optional backup. HiVXE files are updated in place.
section '检查已有 OSCam'
OSCAM_FILES=()
OSCAM_PATH=$(command -v oscam || true)
OSCAM_UNIT=$(systemctl show oscam.service -p FragmentPath --value 2>/dev/null || true)
for target in /usr/local/bin/oscam /usr/local/etc/oscam.* \
    /etc/systemd/system/oscam.service /etc/systemd/system/oscam.service.d \
    "$OSCAM_PATH" "$OSCAM_UNIT"; do
    [[ -n $target && ( -e $target || -L $target ) ]] || continue
    relative=${target#/}
    duplicate=false
    for existing in "${OSCAM_FILES[@]}"; do
        if [[ $existing == "$relative" ]]; then
            duplicate=true
            break
        fi
    done
    if [[ $duplicate == false ]]; then
        OSCAM_FILES+=("$relative")
    fi
done
BACKUP=
if (( ${#OSCAM_FILES[@]} )); then
    printf '检测到已有 OSCam。继续安装将覆盖程序、默认配置和 service。\n'
    while true; do
        printf '是否先备份 OSCam 到 /root/？[Y/n]: '
        if ! IFS= read -r answer; then
            fail '未收到选择，尚未覆盖文件。请重新运行并选择是否备份。'
        fi
        case "$answer" in
            ''|y|Y|yes|YES)
                BACKUP=/root/OSCam_backup_$(date +%Y-%m-%d-%H:%M).tar.gz
                [[ ! -e $BACKUP && ! -L $BACKUP ]] ||
                    fail "备份文件已存在，未覆盖：$BACKUP；请稍后重试或选择不备份。"
                tar -czf "$TEMP_DIR/oscam-backup.tar.gz" -C / -- "${OSCAM_FILES[@]}"
                install -m 0600 "$TEMP_DIR/oscam-backup.tar.gz" "$BACKUP"
                printf 'OSCam 已备份到：%s\n' "$BACKUP"
                break ;;
            n|N|no|NO)
                printf '已选择不备份，直接覆盖 OSCam。\n'
                break ;;
            *) printf '请输入 y（备份）或 n（不备份）。\n' ;;
        esac
    done
else
    printf '未检测到已有 OSCam，执行全新安装。\n'
fi

section '更新 HiVXE 程序及依赖（直接覆盖）'
install -d /usr/local/bin /usr/local/lib/hivxe-ffmpeg /usr/local/etc
for binary in hivxe-ffmpeg hivxe-ffprobe hivxe-top hivxe-transcode; do
    install -m 0755 "$PAYLOAD/bin/$binary" "/usr/local/bin/$binary"
done
cp -a --remove-destination "$PAYLOAD/lib/hivxe-ffmpeg/." /usr/local/lib/hivxe-ffmpeg/
ldconfig

section "安装 OSCam（$OSCAM_VARIANT）"
if systemctl is-active --quiet oscam.service; then
    systemctl stop oscam.service
fi
install -m 0755 "$PAYLOAD/oscam/$OSCAM_VARIANT/oscam" /usr/local/bin/oscam
for config in oscam.conf oscam.server oscam.user oscam.dvbapi; do
    install -m 0600 "$PAYLOAD/oscam/config/$config" "/usr/local/etc/$config"
done
install -m 0644 "$PAYLOAD/oscam/oscam.service" /etc/systemd/system/oscam.service

section '检查 hivxe-ffmpeg'
/usr/local/bin/hivxe-ffmpeg -version
section '检查 hivxe-ffprobe'
/usr/local/bin/hivxe-ffprobe -version
section '检查 hivxe-top'
/usr/local/bin/hivxe-top --help
section '检查 OSCam'
/usr/local/bin/oscam -V
section '启用并启动 OSCam 服务'
systemctl daemon-reload
systemctl enable oscam.service
systemctl restart oscam.service
systemctl is-active --quiet oscam.service || fail 'OSCam 启动失败，请查看 journalctl -u oscam。'

section '安装完成'
printf 'OSCam 版本: %s\n' "$OSCAM_VARIANT"
printf 'WebUI: http://<设备IP>:8888（账号/密码均为 oscam，请修改）。\n'
printf 'OSCam 程序、默认配置和 service 已安装；HiVXE 程序及依赖已更新。\n'
if [[ -n $BACKUP ]]; then
    printf 'OSCam 备份: %s\n' "$BACKUP"
fi
