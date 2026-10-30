#!/usr/bin/env bash
# =============================================================================
# 挂载数据盘到 /opt/luwu（陆吾AI 数据 + 备份都放这里，系统盘只留系统与镜像）
#
# 用法:
#   bash 1b-mount-data-disk.sh                 # 自动识别空数据盘（推荐）
#   bash 1b-mount-data-disk.sh /dev/vdb        # 手动指定设备
#   bash 1b-mount-data-disk.sh /dev/vdb -y     # 免交互（确认过是空盘时用）
#
# 安全校验（任一不满足即中止，不会动盘）:
#   - 设备不是系统盘（不等于 / 所在设备）
#   - 设备无分区表、无文件系统、未挂载
#   - 设备不被 LVM / RAID 占用
# 已挂载或已有数据时会跳过，可安全重复执行。
# =============================================================================
set -euo pipefail

MOUNT_POINT="/opt/luwu"
ASSUME_YES=0
DEV_ARG=""
for a in "$@"; do
    case "$a" in
        -y|--yes) ASSUME_YES=1 ;;
        *) DEV_ARG="$a" ;;
    esac
done

[ "$(id -u)" = 0 ] || { echo "❌ 请用 root 运行"; exit 1; }

ROOT_DEV="$(findmnt -no SOURCE / | sed 's/[0-9]*$//; s/p[0-9]*$//')"
echo "系统盘: $ROOT_DEV"

# ── 已挂载则直接退出（幂等）─────────────────────────────────────────────
if mountpoint -q "$MOUNT_POINT"; then
    echo "✅ $MOUNT_POINT 已挂载:"
    df -h "$MOUNT_POINT" | tail -1
    exit 0
fi

# ── 识别目标盘 ──────────────────────────────────────────────────────────
if [ -z "$DEV_ARG" ]; then
    echo "── 未指定设备，扫描候选数据盘"
    for d in $(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}'); do
        [ "$d" = "$ROOT_DEV" ] && continue
        # 有分区、有文件系统、或已在用 → 跳过
        [ -n "$(lsblk -no NAME "$d" | tail -n +2 | tr -d '[:space:]')" ] && continue
        [ -n "$(blkid -o value -s TYPE "$d" 2>/dev/null || true)" ] && continue
        findmnt -S "$d" >/dev/null 2>&1 && continue
        DEV="$d"; break
    done
else
    DEV="$DEV_ARG"
fi

if [ -z "${DEV:-}" ]; then
    echo "❌ 没找到可用的空数据盘。手动确认后指定: bash $0 /dev/vdX"
    lsblk -f
    exit 1
fi

# ── 安全校验 ────────────────────────────────────────────────────────────
echo "── 目标设备: $DEV"
[ "$DEV" != "$ROOT_DEV" ] || { echo "❌ 这是系统盘，拒绝操作"; exit 1; }
[ -b "$DEV" ] || { echo "❌ $DEV 不是块设备"; exit 1; }
if [ -n "$(lsblk -no NAME "$DEV" | tail -n +2 | tr -d '[:space:]')" ]; then
    echo "❌ $DEV 已有分区，拒绝操作；请人工确认"; lsblk -f "$DEV"; exit 1
fi
if [ -n "$(blkid -o value -s TYPE "$DEV" 2>/dev/null || true)" ]; then
    echo "❌ $DEV 已有文件系统（$(blkid -o value -s TYPE "$DEV")），拒绝操作"; exit 1
fi
if findmnt -S "$DEV" >/dev/null 2>&1; then
    echo "❌ $DEV 已挂载，拒绝操作"; exit 1
fi
for t in $(lsblk -no TYPE "$DEV"); do
    case "$t" in lvm|raid*) echo "❌ $DEV 被 $t 占用，拒绝操作"; exit 1 ;; esac
done

SIZE="$(lsblk -dno SIZE "$DEV")"
echo "   容量: $SIZE（即将格式化为 ext4，盘上现有数据会全部丢失）"
if [ "$ASSUME_YES" != 1 ]; then
    read -r -p "确认格式化 $DEV ? 输入 yes 继续: " ans
    [ "$ans" = "yes" ] || { echo "已取消"; exit 1; }
fi

# ── 格式化并挂载 ────────────────────────────────────────────────────────
echo "── mkfs.ext4 $DEV"
mkfs.ext4 -F -m 1 -L luwu-data "$DEV" >/dev/null

mkdir -p "$MOUNT_POINT"
UUID="$(blkid -o value -s UUID "$DEV")"
if ! grep -q "$UUID" /etc/fstab; then
    cp /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
    echo "UUID=$UUID  $MOUNT_POINT  ext4  defaults,nofail,noatime  0 2" >> /etc/fstab
    echo "   已写入 /etc/fstab（nofail: 盘异常不影响系统启动）"
fi
mount -a
mountpoint -q "$MOUNT_POINT" || { echo "❌ 挂载失败"; exit 1; }

mkdir -p "$MOUNT_POINT/data" "$MOUNT_POINT/backup"

echo ""
echo "✅ 数据盘就绪"
df -h "$MOUNT_POINT" | tail -1
echo "   数据目录: $MOUNT_POINT/data    备份目录: $MOUNT_POINT/backup"
echo "   下一步: bash 2-fetch-code.sh"
