#!/bin/bash
# ============================================================
# LVM + 磁盘管理交互式脚本（全面增强版）
# 功能：LVM 管理、磁盘分区管理、格式化挂载、详细信息查询
# 特性：自动检测系统版本，使用对应命令；支持多选输入
# 使用：root 或 sudo 运行
# ============================================================

set -o pipefail

# ---------- 颜色定义 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---------- 全局变量 ----------
OS_FAMILY=""
PKG_MANAGER=""
PART_RELOAD_CMD=""

# ---------- 检测操作系统 ----------
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID_LIKE" in
            *rhel*|*fedora*|*centos*)
                OS_FAMILY="redhat"
                PKG_MANAGER="yum"
                PART_RELOAD_CMD="partprobe"
                ;;
            *debian*|*ubuntu*)
                OS_FAMILY="debian"
                PKG_MANAGER="apt-get"
                PART_RELOAD_CMD="partx -u"
                ;;
            *suse*)
                OS_FAMILY="suse"
                PKG_MANAGER="zypper"
                PART_RELOAD_CMD="partprobe"
                ;;
            *)
                OS_FAMILY="unknown"
                PKG_MANAGER="yum"
                PART_RELOAD_CMD="partprobe"
                ;;
        esac
    else
        OS_FAMILY="unknown"
        PKG_MANAGER="yum"
        PART_RELOAD_CMD="partprobe"
    fi
    echo -e "${CYAN}检测到系统家族：${OS_FAMILY}，包管理器：${PKG_MANAGER}${NC}"
}

# ---------- 权限检查 ----------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：请使用 root 或 sudo 运行此脚本${NC}"
        exit 1
    fi
}

# ---------- 依赖检查 ----------
check_deps() {
    local deps=("lsblk" "pvcreate" "vgcreate" "lvcreate" "pvremove" "vgremove" "lvremove" \
                 "lvextend" "vgextend" "vgreduce" "mkfs.ext4" "mkfs.xfs" "mount" "umount" \
                 "blkid" "parted" "fdisk" "pvs" "vgs" "lvs" "resize2fs" "xfs_growfs")
    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}错误：以下必需命令缺失：${NC}"
        printf '%s\n' "${missing[@]}"
        echo -e "${YELLOW}请使用 ${PKG_MANAGER} 安装：${PKG_MANAGER} install ${missing[*]}${NC}"
        exit 1
    fi
}

# ---------- 解析逗号分隔选择 ----------
parse_choices() {
    local input="$1"
    SELECTED_INDICES=()
    local IFS=$' ,'
    for num in $input; do
        if [[ "$num" =~ ^[0-9]+$ ]]; then
            if [[ ! " ${SELECTED_INDICES[@]} " =~ " $num " ]]; then
                SELECTED_INDICES+=("$num")
            fi
        fi
    done
    [ ${#SELECTED_INDICES[@]} -eq 0 ] && return 1 || return 0
}

# ---------- 刷新分区表 ----------
reload_partition_table() {
    local disk="$1"
    echo -e "${GREEN}刷新分区表...${NC}"
    if [ "$PART_RELOAD_CMD" = "partx -u" ]; then
        partx -u "$disk" 2>/dev/null || partprobe "$disk" 2>/dev/null || true
    else
        partprobe "$disk" 2>/dev/null || partx -u "$disk" 2>/dev/null || true
    fi
    sleep 2
}

# ============================================================
# 通用选择函数
# ============================================================

# 列出磁盘
list_disks() {
    echo -e "${YELLOW}可用磁盘列表：${NC}"
    lsblk -d -n -o NAME,SIZE,TYPE,MODEL | grep -v -E 'loop|rom|cdrom' | awk '{print "/dev/"$1"  "$2"  "$4}'
}

# 选择磁盘
select_disk() {
    local disks=()
    while IFS= read -r line; do
        disks+=("$line")
    done < <(lsblk -d -n -o NAME,SIZE | grep -v -E 'loop|rom|cdrom' | awk '{print "/dev/"$1" "$2}')

    [ ${#disks[@]} -eq 0 ] && { echo -e "${RED}没有找到可用磁盘！${NC}"; return 1; }

    echo -e "${YELLOW}请选择磁盘（输入编号）：${NC}"
    local i=1
    for d in "${disks[@]}"; do
        echo "  $i) $d"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local choice
    while true; do
        read -p "选择: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#disks[@]} ]; then
            break
        else
            echo -e "${RED}无效选择，请重新输入${NC}"
        fi
    done
    [ "$choice" -eq 0 ] && return 1
    selected_disk=$(echo "${disks[$((choice-1))]}" | awk '{print $1}')
    echo -e "${GREEN}已选择磁盘：$selected_disk${NC}"
}

# 检查磁盘是否已有分区
disk_has_partitions() {
    local disk="$1"
    lsblk -n -o NAME,TYPE "$disk" | grep -q 'part'
}

# 列出分区
list_partitions() {
    local disk="$1"
    echo -e "${YELLOW}磁盘 $disk 上的分区：${NC}"
    lsblk -n -o NAME,SIZE,FSTYPE "$disk" | grep 'part' | awk '{print "/dev/"$1"  "$2"  "$3}'
}

# 选择分区
select_partition() {
    local disk="$1"
    local parts=()
    while IFS= read -r line; do
        parts+=("$line")
    done < <(lsblk -n -o NAME,SIZE "$disk" | grep 'part' | awk '{print "/dev/"$1" "$2}')

    [ ${#parts[@]} -eq 0 ] && return 1

    echo -e "${YELLOW}请选择分区（输入编号）：${NC}"
    local i=1
    for p in "${parts[@]}"; do
        echo "  $i) $p"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local choice
    while true; do
        read -p "选择: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#parts[@]} ]; then
            break
        else
            echo -e "${RED}无效选择，请重新输入${NC}"
        fi
    done
    [ "$choice" -eq 0 ] && return 1
    selected_partition=$(echo "${parts[$((choice-1))]}" | awk '{print $1}')
    echo -e "${GREEN}已选择分区：$selected_partition${NC}"
}

# ---------- 创建全盘分区（LVM 用） ----------
create_partition_on_disk() {
    local disk="$1"
    echo -e "${YELLOW}警告：此操作将擦除磁盘 $disk 上的所有数据！${NC}"
    read -p "确认继续？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    echo -e "${GREEN}正在创建 GPT 分区表和全盘分区...${NC}"
    parted -s "$disk" mklabel gpt
    parted -s "$disk" mkpart primary 0% 100%
    reload_partition_table "$disk"

    local new_part=$(lsblk -n -o NAME "$disk" | grep 'part' | head -n1)
    [ -z "$new_part" ] && { echo -e "${RED}分区创建失败或未检测到分区${NC}"; return 1; }
    selected_partition="/dev/$new_part"
    echo -e "${GREEN}已创建分区：$selected_partition${NC}"
}

# ---------- 准备 PV 目标 ----------
prepare_pv_target() {
    select_disk || return 1
    local disk="$selected_disk"
    selected_partition=""

    if disk_has_partitions "$disk"; then
        echo -e "${YELLOW}磁盘 $disk 已有分区：${NC}"
        list_partitions "$disk"
        read -p "是否使用现有分区？(y/N): " use_existing
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            select_partition "$disk" || return 1
            [ -z "$selected_partition" ] && return 1
        else
            create_partition_on_disk "$disk" || return 1
        fi
    else
        echo -e "${YELLOW}磁盘 $disk 没有分区${NC}"
        read -p "是否在整个磁盘上直接创建 PV（不分区）？(y/N): " use_whole
        if [[ "$use_whole" =~ ^[Yy]$ ]]; then
            selected_partition="$disk"
            echo -e "${YELLOW}使用整个磁盘作为 PV（不推荐，但支持）${NC}"
        else
            create_partition_on_disk "$disk" || return 1
        fi
    fi
}

# ---------- 获取未使用 PV ----------
get_unused_pvs() {
    pvs --noheadings -o pv_name,vg_name | awk '$2 == "" {print $1}' | tr -d ' '
}

# ---------- 获取有空间的 VG ----------
get_vgs_with_free_space() {
    vgs --noheadings -o vg_name,vg_free | awk '$2 != "0" {print $1}' | tr -d ' '
}

# ---------- 显示未使用 PV ----------
show_unused_pvs() {
    local unused=$(get_unused_pvs)
    if [ -z "$unused" ]; then
        echo -e "${YELLOW}没有未使用的 PV${NC}"
    else
        echo -e "${YELLOW}未使用的 PV（可加入 VG）：${NC}"
        pvs --noheadings -o pv_name,size,vg_name | awk '$3 == "" {print $1"  "$2}'
    fi
}

# ============================================================
# LVM 信息查询函数
# ============================================================

show_pv_details() {
    echo -e "${YELLOW}===== 物理卷详细信息 =====${NC}"
    pvs -o pv_name,vg_name,pv_size,pv_free,pv_used,dev_size,pv_attr
}

show_vg_details() {
    echo -e "${YELLOW}===== 卷组详细信息 =====${NC}"
    vgs -o vg_name,vg_size,vg_free,vg_extent_size,vg_extent_count,vg_attr,pv_count,lv_count
}

show_lv_details() {
    echo -e "${YELLOW}===== 逻辑卷详细信息 =====${NC}"
    lvs -o lv_name,vg_name,lv_size,lv_attr,lv_path,origin,data_percent
}

show_disk_details() {
    echo -e "${YELLOW}===== 磁盘详细信息 =====${NC}"
    echo -e "${BLUE}所有磁盘：${NC}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
    echo -e "${BLUE}分区表信息：${NC}"
    for disk in $(lsblk -d -n -o NAME | grep -v -E 'loop|rom|cdrom'); do
        echo -e "${CYAN}/dev/$disk${NC}"
        fdisk -l "/dev/$disk" 2>/dev/null | grep -E 'Disk /dev|Disklabel type|Disk model'
    done
}

# 详细信息查询子菜单
info_menu() {
    while true; do
        echo ""
        echo -e "${GREEN}========== 信息查询 ==========${NC}"
        echo "  1) 查看所有 PV 详细信息"
        echo "  2) 查看所有 VG 详细信息"
        echo "  3) 查看所有 LV 详细信息"
        echo "  4) 查看磁盘和分区详细信息"
        echo "  0) 返回主菜单"
        echo -e "${GREEN}==============================${NC}"
        read -p "请选择操作: " choice
        case "$choice" in
            1) show_pv_details ;;
            2) show_vg_details ;;
            3) show_lv_details ;;
            4) show_disk_details ;;
            0) return ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
    done
}

# ============================================================
# LVM 操作函数
# ============================================================

# 创建 PV
create_pv() {
    echo -e "${YELLOW}===== 创建物理卷 (PV) =====${NC}"
    prepare_pv_target || return 1
    local target="$selected_partition"
    echo -e "${YELLOW}目标设备：$target${NC}"

    if pvs "$target" &>/dev/null; then
        echo -e "${YELLOW}警告：$target 已经是物理卷${NC}"
        local vg=$(pvs --noheadings -o vg_name "$target" | tr -d ' ')
        if [ -n "$vg" ]; then
            echo -e "${RED}错误：该 PV 已属于 VG $vg，无法重新创建。${NC}"
            return 1
        fi
        read -p "是否强制重新创建 PV？(y/N): " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }
        pvcreate -f "$target" || return 1
        echo -e "${GREEN}PV 已强制重建${NC}"
    else
        read -p "确认在 $target 上创建 PV？(y/N): " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }
        pvcreate "$target" || return 1
        echo -e "${GREEN}PV 创建成功${NC}"
    fi
}

# 创建 VG（支持多选 PV）
create_vg() {
    echo -e "${YELLOW}===== 创建卷组 (VG) =====${NC}"
    local unused_pvs=($(get_unused_pvs))
    [ ${#unused_pvs[@]} -eq 0 ] && { echo -e "${RED}没有可用的未使用 PV。${NC}"; return 1; }

    echo -e "${YELLOW}可用的未使用 PV（可多选，用逗号分隔编号）：${NC}"
    local i=1
    for pv in "${unused_pvs[@]}"; do
        echo "  $i) $pv"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local input
    read -p "选择要加入 VG 的 PV（例如 1,2,3）：" input
    [ -z "$input" ] || [ "$input" = "0" ] && return 1

    parse_choices "$input" || { echo -e "${RED}无效输入${NC}"; return 1; }

    local selected_pvs=()
    for num in "${SELECTED_INDICES[@]}"; do
        if [ "$num" -ge 1 ] && [ "$num" -le ${#unused_pvs[@]} ]; then
            selected_pvs+=("${unused_pvs[$((num-1))]}")
        else
            echo -e "${RED}编号 $num 超出范围，已忽略${NC}"
        fi
    done

    [ ${#selected_pvs[@]} -eq 0 ] && { echo -e "${RED}没有有效的 PV 被选择${NC}"; return 1; }

    read -p "请输入 VG 名称: " vgname
    [ -z "$vgname" ] && { echo -e "${RED}VG 名称不能为空${NC}"; return 1; }
    vgs "$vgname" &>/dev/null && { echo -e "${RED}错误：VG $vgname 已存在${NC}"; return 1; }

    echo -e "${GREEN}正在使用以下 PV 创建 VG $vgname：${NC}"
    printf '%s\n' "${selected_pvs[@]}"
    vgcreate "$vgname" "${selected_pvs[@]}" && echo -e "${GREEN}VG $vgname 创建成功${NC}" || { echo -e "${RED}VG 创建失败${NC}"; return 1; }
}

# 创建 LV
create_lv() {
    echo -e "${YELLOW}===== 创建逻辑卷 (LV) =====${NC}"
    local vg_list=($(get_vgs_with_free_space))
    [ ${#vg_list[@]} -eq 0 ] && { echo -e "${RED}没有可用空间的 VG。${NC}"; return 1; }

    echo -e "${YELLOW}有可用空间的 VG：${NC}"
    local i=1
    for vg in "${vg_list[@]}"; do
        echo "  $i) $vg"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local choice
    while true; do
        read -p "选择 VG（编号）: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#vg_list[@]} ]; then
            break
        else
            echo -e "${RED}无效选择${NC}"
        fi
    done
    [ "$choice" -eq 0 ] && return 1
    selected_vg="${vg_list[$((choice-1))]}"

    read -p "请输入 LV 名称: " lvname
    [ -z "$lvname" ] && { echo -e "${RED}LV 名称不能为空${NC}"; return 1; }
    lvs "$selected_vg/$lvname" &>/dev/null && { echo -e "${RED}错误：LV $lvname 已存在${NC}"; return 1; }

    read -p "请输入 LV 大小（例如 10G、500M）: " lvsize
    [ -z "$lvsize" ] && { echo -e "${RED}大小不能为空${NC}"; return 1; }

    lvcreate -L "$lvsize" -n "$lvname" "$selected_vg" && echo -e "${GREEN}LV $lvname 创建成功${NC}" || { echo -e "${RED}LV 创建失败${NC}"; return 1; }
}

# 扩展 VG（添加 PV）
extend_vg() {
    echo -e "${YELLOW}===== 扩展卷组 (向现有 VG 添加 PV) =====${NC}"
    local vg_list=($(vgs --noheadings -o vg_name | tr -d ' '))
    [ ${#vg_list[@]} -eq 0 ] && { echo -e "${RED}没有可用的 VG。${NC}"; return 1; }

    echo -e "${YELLOW}请选择要扩展的 VG：${NC}"
    local i=1
    for vg in "${vg_list[@]}"; do
        echo "  $i) $vg"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local choice
    while true; do
        read -p "选择 VG（编号）: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#vg_list[@]} ]; then
            break
        else
            echo -e "${RED}无效选择${NC}"
        fi
    done
    [ "$choice" -eq 0 ] && return 1
    selected_vg="${vg_list[$((choice-1))]}"

    # 获取未使用的 PV
    local unused_pvs=($(get_unused_pvs))
    [ ${#unused_pvs[@]} -eq 0 ] && { echo -e "${RED}没有未使用的 PV 可用于添加。${NC}"; return 1; }

    echo -e "${YELLOW}可用的未使用 PV（可多选，逗号分隔编号）：${NC}"
    local j=1
    for pv in "${unused_pvs[@]}"; do
        echo "  $j) $pv"
        ((j++))
    done
    echo "  0) 返回上级菜单（默认）"

    local input
    read -p "选择要添加到 VG 的 PV： " input
    [ -z "$input" ] || [ "$input" = "0" ] && return 1

    parse_choices "$input" || { echo -e "${RED}无效输入${NC}"; return 1; }

    local selected_pvs=()
    for num in "${SELECTED_INDICES[@]}"; do
        if [ "$num" -ge 1 ] && [ "$num" -le ${#unused_pvs[@]} ]; then
            selected_pvs+=("${unused_pvs[$((num-1))]}")
        else
            echo -e "${RED}编号 $num 超出范围，已忽略${NC}"
        fi
    done

    [ ${#selected_pvs[@]} -eq 0 ] && { echo -e "${RED}没有有效的 PV 被选择${NC}"; return 1; }

    echo -e "${YELLOW}即将向 VG $selected_vg 添加以下 PV：${NC}"
    printf '%s\n' "${selected_pvs[@]}"
    read -p "确认继续？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    vgextend "$selected_vg" "${selected_pvs[@]}" && echo -e "${GREEN}VG 扩展成功${NC}" || echo -e "${RED}VG 扩展失败${NC}"
}

# 缩减 VG（移除 PV）
reduce_vg() {
    echo -e "${YELLOW}===== 缩减卷组 (从 VG 移除 PV) =====${NC}"
    local vg_list=($(vgs --noheadings -o vg_name | tr -d ' '))
    [ ${#vg_list[@]} -eq 0 ] && { echo -e "${RED}没有可用的 VG。${NC}"; return 1; }

    echo -e "${YELLOW}请选择要缩减的 VG：${NC}"
    local i=1
    for vg in "${vg_list[@]}"; do
        echo "  $i) $vg"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local choice
    while true; do
        read -p "选择 VG（编号）: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#vg_list[@]} ]; then
            break
        else
            echo -e "${RED}无效选择${NC}"
        fi
    done
    [ "$choice" -eq 0 ] && return 1
    selected_vg="${vg_list[$((choice-1))]}"

    # 获取该 VG 中的所有 PV
    local pv_list=($(pvs --noheadings -o pv_name,vg_name | awk -v vg="$selected_vg" '$2==vg {print $1}' | tr -d ' '))
    [ ${#pv_list[@]} -eq 0 ] && { echo -e "${RED}VG $selected_vg 中没有 PV。${NC}"; return 1; }

    echo -e "${YELLOW}当前 VG $selected_vg 中的 PV（可多选，逗号分隔编号）：${NC}"
    local j=1
    for pv in "${pv_list[@]}"; do
        echo "  $j) $pv"
        ((j++))
    done
    echo "  0) 返回上级菜单（默认）"

    local input
    read -p "选择要从 VG 移除的 PV： " input
    [ -z "$input" ] || [ "$input" = "0" ] && return 1

    parse_choices "$input" || { echo -e "${RED}无效输入${NC}"; return 1; }

    local selected_pvs=()
    for num in "${SELECTED_INDICES[@]}"; do
        if [ "$num" -ge 1 ] && [ "$num" -le ${#pv_list[@]} ]; then
            selected_pvs+=("${pv_list[$((num-1))]}")
        else
            echo -e "${RED}编号 $num 超出范围，已忽略${NC}"
        fi
    done

    [ ${#selected_pvs[@]} -eq 0 ] && { echo -e "${RED}没有有效的 PV 被选择${NC}"; return 1; }

    # 检查 PV 上是否有数据（不能直接移除包含数据的 PV）
    for pv in "${selected_pvs[@]}"; do
        local used=$(pvs --noheadings -o pv_used "$pv" | tr -d ' ')
        if [ "$used" != "0" ]; then
            echo -e "${RED}错误：PV $pv 上仍有数据，无法从 VG 中移除。请先迁移数据或删除 LV。${NC}"
            return 1
        fi
    done

    echo -e "${YELLOW}即将从 VG $selected_vg 移除以下 PV：${NC}"
    printf '%s\n' "${selected_pvs[@]}"
    read -p "确认继续？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    vgreduce "$selected_vg" "${selected_pvs[@]}" && echo -e "${GREEN}VG 缩减成功${NC}" || echo -e "${RED}VG 缩减失败${NC}"
}

# 创建 LV 快照
create_lv_snapshot() {
    echo -e "${YELLOW}===== 创建 LV 快照 =====${NC}"
    local lv_list=($(lvs --noheadings -o lv_path,origin | awk '$2=="" {print $1}' | tr -d ' '))  # 只选择非快照的 LV
    [ ${#lv_list[@]} -eq 0 ] && { echo -e "${RED}没有可用的源 LV。${NC}"; return 1; }

    echo -e "${YELLOW}请选择要创建快照的源 LV：${NC}"
    local i=1
    for lv in "${lv_list[@]}"; do
        echo "  $i) $lv"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local choice
    while true; do
        read -p "选择: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#lv_list[@]} ]; then
            break
        else
            echo -e "${RED}无效选择${NC}"
        fi
    done
    [ "$choice" -eq 0 ] && return 1
    selected_lv="${lv_list[$((choice-1))]}"

    local vg_name=$(lvs --noheadings -o vg_name "$selected_lv" | tr -d ' ')
    read -p "请输入快照名称: " snap_name
    [ -z "$snap_name" ] && { echo -e "${RED}快照名称不能为空${NC}"; return 1; }
    lvs "$vg_name/$snap_name" &>/dev/null && { echo -e "${RED}错误：快照 $snap_name 已存在${NC}"; return 1; }

    read -p "请输入快照大小（例如 5G）: " snap_size
    [ -z "$snap_size" ] && { echo -e "${RED}大小不能为空${NC}"; return 1; }

    lvcreate -L "$snap_size" -s -n "$snap_name" "$selected_lv" && echo -e "${GREEN}快照 $snap_name 创建成功${NC}" || echo -e "${RED}快照创建失败${NC}"
}

# ---------- 格式化并挂载 LV ----------
format_and_mount_lv() {
    echo -e "${YELLOW}===== 格式化并挂载逻辑卷 =====${NC}"
    local lv_list=($(lvs --noheadings -o lv_path,origin | awk '$2=="" {print $1}' | tr -d ' '))  # 排除快照
    [ ${#lv_list[@]} -eq 0 ] && { echo -e "${RED}没有可用的 LV${NC}"; return 1; }

    echo -e "${YELLOW}请选择要格式化的 LV：${NC}"
    local i=1
    for lv in "${lv_list[@]}"; do
        echo "  $i) $lv"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"
    local choice
    while true; do
        read -p "选择: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#lv_list[@]} ]; then
            break
        else
            echo -e "${RED}无效选择${NC}"
        fi
    done
    [ "$choice" -eq 0 ] && return 1
    selected_lv="${lv_list[$((choice-1))]}"

    mount | grep -q "$selected_lv" && { echo -e "${YELLOW}警告：$selected_lv 已挂载，请先卸载${NC}"; return 1; }

    echo -e "${YELLOW}请选择文件系统类型：${NC}"
    echo "  1) ext4"
    echo "  2) xfs"
    echo "  0) 返回上级菜单（默认）"
    local fs_choice
    while true; do
        read -p "选择: " fs_choice
        if [[ "$fs_choice" =~ ^[0-2]$ ]]; then
            break
        else
            echo -e "${RED}无效选择${NC}"
        fi
    done
    [ "$fs_choice" -eq 0 ] && return 1

    local fs_type
    [ "$fs_choice" -eq 1 ] && fs_type="ext4" || fs_type="xfs"

    read -p "警告：格式化将擦除 $selected_lv 上的所有数据！确认？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    echo -e "${GREEN}正在格式化 $selected_lv 为 $fs_type ...${NC}"
    if [ "$fs_type" = "ext4" ]; then
        mkfs.ext4 "$selected_lv"
    else
        mkfs.xfs -f "$selected_lv"
    fi
    [ $? -ne 0 ] && { echo -e "${RED}格式化失败${NC}"; return 1; }

    read -p "请输入挂载点（例如 /mnt/data）: " mountpoint
    [ -z "$mountpoint" ] && { echo -e "${RED}挂载点不能为空${NC}"; return 1; }
    [ ! -d "$mountpoint" ] && mkdir -p "$mountpoint" && echo -e "${GREEN}创建挂载点目录 $mountpoint${NC}"

    mount "$selected_lv" "$mountpoint" && echo -e "${GREEN}挂载成功！${NC}" || { echo -e "${RED}挂载失败${NC}"; return 1; }

    read -p "是否将挂载信息写入 /etc/fstab？(y/N): " add_fstab
    if [[ "$add_fstab" =~ ^[Yy]$ ]]; then
        local uuid=$(blkid -s UUID -o value "$selected_lv")
        if [ -n "$uuid" ]; then
            echo "UUID=$uuid $mountpoint $fs_type defaults 0 2" >> /etc/fstab
            echo -e "${GREEN}已添加到 /etc/fstab${NC}"
        else
            echo -e "${YELLOW}无法获取 UUID，请手动添加${NC}"
        fi
    fi
}

# ---------- 删除 LV ----------
delete_lv() {
    echo -e "${YELLOW}===== 删除逻辑卷 (LV) =====${NC}"
    local lv_list=($(lvs --noheadings -o lv_path | tr -d ' '))
    [ ${#lv_list[@]} -eq 0 ] && { echo -e "${RED}没有可用的 LV${NC}"; return 1; }

    echo -e "${YELLOW}请选择要删除的 LV（可多选，逗号分隔）：${NC}"
    local i=1
    for lv in "${lv_list[@]}"; do
        echo "  $i) $lv"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local input
    read -p "选择: " input
    [ -z "$input" ] || [ "$input" = "0" ] && return 1

    parse_choices "$input" || { echo -e "${RED}无效输入${NC}"; return 1; }

    local selected_lvs=()
    for num in "${SELECTED_INDICES[@]}"; do
        if [ "$num" -ge 1 ] && [ "$num" -le ${#lv_list[@]} ]; then
            selected_lvs+=("${lv_list[$((num-1))]}")
        else
            echo -e "${RED}编号 $num 超出范围，已忽略${NC}"
        fi
    done

    [ ${#selected_lvs[@]} -eq 0 ] && { echo -e "${RED}没有有效的 LV 被选择${NC}"; return 1; }

    echo -e "${YELLOW}以下 LV 将被删除：${NC}"
    printf '%s\n' "${selected_lvs[@]}"
    read -p "确认删除所有选中的 LV？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    for lv in "${selected_lvs[@]}"; do
        if mount | grep -q "$lv"; then
            echo -e "${YELLOW}警告：$lv 已挂载，尝试自动卸载...${NC}"
            umount "$lv" || { echo -e "${RED}卸载 $lv 失败，跳过${NC}"; continue; }
        fi
        lvremove -f "$lv" && echo -e "${GREEN}LV $lv 已删除${NC}" || echo -e "${RED}删除 LV $lv 失败${NC}"
    done
}

# ---------- 删除 VG ----------
delete_vg() {
    echo -e "${YELLOW}===== 删除卷组 (VG) =====${NC}"
    local vg_list=($(vgs --noheadings -o vg_name | tr -d ' '))
    [ ${#vg_list[@]} -eq 0 ] && { echo -e "${RED}没有可用的 VG${NC}"; return 1; }

    echo -e "${YELLOW}请选择要删除的 VG（可多选，逗号分隔）：${NC}"
    local i=1
    for vg in "${vg_list[@]}"; do
        echo "  $i) $vg"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local input
    read -p "选择: " input
    [ -z "$input" ] || [ "$input" = "0" ] && return 1

    parse_choices "$input" || { echo -e "${RED}无效输入${NC}"; return 1; }

    local selected_vgs=()
    for num in "${SELECTED_INDICES[@]}"; do
        if [ "$num" -ge 1 ] && [ "$num" -le ${#vg_list[@]} ]; then
            selected_vgs+=("${vg_list[$((num-1))]}")
        else
            echo -e "${RED}编号 $num 超出范围，已忽略${NC}"
        fi
    done

    [ ${#selected_vgs[@]} -eq 0 ] && { echo -e "${RED}没有有效的 VG 被选择${NC}"; return 1; }

    for vg in "${selected_vgs[@]}"; do
        local lv_count=$(lvs --noheadings "$vg" | wc -l)
        if [ "$lv_count" -gt 0 ]; then
            echo -e "${RED}错误：VG $vg 中还有 LV，请先删除所有 LV。${NC}"
            return 1
        fi
    done

    echo -e "${YELLOW}以下 VG 将被删除：${NC}"
    printf '%s\n' "${selected_vgs[@]}"
    read -p "确认删除所有选中的 VG？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    for vg in "${selected_vgs[@]}"; do
        vgremove "$vg" && echo -e "${GREEN}VG $vg 已删除${NC}" || echo -e "${RED}删除 VG $vg 失败${NC}"
    done
}

# ---------- 删除 PV ----------
delete_pv() {
    echo -e "${YELLOW}===== 删除物理卷 (PV) =====${NC}"
    local pv_list=($(pvs --noheadings -o pv_name | tr -d ' '))
    [ ${#pv_list[@]} -eq 0 ] && { echo -e "${RED}没有可用的 PV${NC}"; return 1; }

    echo -e "${YELLOW}请选择要删除的 PV（可多选，逗号分隔）：${NC}"
    local i=1
    for pv in "${pv_list[@]}"; do
        echo "  $i) $pv"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local input
    read -p "选择: " input
    [ -z "$input" ] || [ "$input" = "0" ] && return 1

    parse_choices "$input" || { echo -e "${RED}无效输入${NC}"; return 1; }

    local selected_pvs=()
    for num in "${SELECTED_INDICES[@]}"; do
        if [ "$num" -ge 1 ] && [ "$num" -le ${#pv_list[@]} ]; then
            selected_pvs+=("${pv_list[$((num-1))]}")
        else
            echo -e "${RED}编号 $num 超出范围，已忽略${NC}"
        fi
    done

    [ ${#selected_pvs[@]} -eq 0 ] && { echo -e "${RED}没有有效的 PV 被选择${NC}"; return 1; }

    for pv in "${selected_pvs[@]}"; do
        local vg=$(pvs --noheadings -o vg_name "$pv" | tr -d ' ')
        if [ -n "$vg" ]; then
            echo -e "${RED}错误：PV $pv 属于 VG $vg，请先从 VG 中移除该 PV。${NC}"
            return 1
        fi
    done

    echo -e "${YELLOW}以下 PV 将被删除：${NC}"
    printf '%s\n' "${selected_pvs[@]}"
    read -p "确认删除所有选中的 PV？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    for pv in "${selected_pvs[@]}"; do
        pvremove "$pv" && echo -e "${GREEN}PV $pv 已删除${NC}" || echo -e "${RED}删除 PV $pv 失败${NC}"
    done
}

# ---------- 扩展 LV ----------
extend_lv() {
    echo -e "${YELLOW}===== 扩展逻辑卷 (LV) =====${NC}"
    local lv_list=($(lvs --noheadings -o lv_path | tr -d ' '))
    [ ${#lv_list[@]} -eq 0 ] && { echo -e "${RED}没有可用的 LV${NC}"; return 1; }

    echo -e "${YELLOW}请选择要扩展的 LV：${NC}"
    local i=1
    for lv in "${lv_list[@]}"; do
        echo "  $i) $lv"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"
    local choice
    while true; do
        read -p "选择: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -le ${#lv_list[@]} ]; then
            break
        else
            echo -e "${RED}无效选择${NC}"
        fi
    done
    [ "$choice" -eq 0 ] && return 1
    selected_lv="${lv_list[$((choice-1))]}"

    local vg_name=$(lvs --noheadings -o vg_name "$selected_lv" | tr -d ' ')
    echo -e "${YELLOW}当前 VG $vg_name 可用空间：${NC}"
    vgs "$vg_name" --noheadings -o vg_free

    read -p "请输入要增加的大小（例如 +5G）: " extend_size
    [ -z "$extend_size" ] && { echo -e "${RED}大小不能为空${NC}"; return 1; }

    local mount_point=""
    if mount | grep -q "$selected_lv"; then
        mount_point=$(mount | grep "$selected_lv" | awk '{print $3}')
        echo -e "${YELLOW}LV 当前挂载在 $mount_point${NC}"
    else
        echo -e "${YELLOW}LV 未挂载，扩展后无需调整文件系统${NC}"
    fi

    lvextend -L "$extend_size" "$selected_lv" && echo -e "${GREEN}LV 扩展成功${NC}" || { echo -e "${RED}扩展失败${NC}"; return 1; }

    if [ -n "$mount_point" ]; then
        local fs_type=$(blkid -s TYPE -o value "$selected_lv")
        if [ "$fs_type" = "ext4" ]; then
            resize2fs "$selected_lv"
            echo -e "${GREEN}ext4 文件系统已扩展${NC}"
        elif [ "$fs_type" = "xfs" ]; then
            xfs_growfs "$mount_point"
            echo -e "${GREEN}xfs 文件系统已扩展${NC}"
        else
            echo -e "${YELLOW}未知文件系统类型，请手动扩展${NC}"
        fi
    fi
}

# ============================================================
# 磁盘管理模块
# ============================================================

show_disk_details() {
    echo -e "${YELLOW}===== 磁盘详细信息 =====${NC}"
    echo -e "${BLUE}所有磁盘：${NC}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
    echo -e "${BLUE}分区表信息：${NC}"
    for disk in $(lsblk -d -n -o NAME | grep -v -E 'loop|rom|cdrom'); do
        echo -e "${CYAN}/dev/$disk${NC}"
        fdisk -l "/dev/$disk" 2>/dev/null | grep -E 'Disk /dev|Disklabel type|Disk model'
    done
}

list_all_partitions() {
    echo -e "${YELLOW}所有分区列表：${NC}"
    lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT | grep -E 'part|lvm' | awk '{print "/dev/"$1"  "$2"  "$3}'
}

select_disk_for_partition() {
    select_disk || return 1
    local disk="$selected_disk"
    echo -e "${YELLOW}当前磁盘 $disk 的分区表：${NC}"
    parted -s "$disk" print 2>/dev/null || fdisk -l "$disk"
}

create_partition_manual() {
    echo -e "${YELLOW}===== 创建分区 =====${NC}"
    select_disk_for_partition || return 1
    local disk="$selected_disk"

    local has_parts=$(lsblk -n -o NAME "$disk" | grep -c 'part')
    echo -e "${YELLOW}当前磁盘 $disk 上有 $has_parts 个分区${NC}"

    echo -e "${YELLOW}请选择分区表类型：${NC}"
    echo "  1) GPT (推荐)"
    echo "  2) MBR (msdos)"
    echo "  0) 返回"
    local table_choice
    while true; do
        read -p "选择: " table_choice
        [[ "$table_choice" =~ ^[0-2]$ ]] && break || echo -e "${RED}无效选择${NC}"
    done
    [ "$table_choice" -eq 0 ] && return 1

    local table_type
    [ "$table_choice" -eq 1 ] && table_type="gpt" || table_type="msdos"

    echo -e "${RED}警告：修改分区表可能会擦除磁盘上的所有数据！${NC}"
    read -p "确认继续？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    if [ "$has_parts" -eq 0 ]; then
        parted -s "$disk" mklabel "$table_type"
        echo -e "${GREEN}已创建 $table_type 分区表${NC}"
    else
        echo -e "${YELLOW}磁盘上已有分区，跳过创建分区表步骤${NC}"
    fi

    local part_type="primary"
    if [ "$table_type" = "msdos" ]; then
        echo -e "${YELLOW}请选择分区类型：${NC}"
        echo "  1) 主分区 (primary)"
        echo "  2) 逻辑分区 (logical)"
        echo "  0) 返回"
        local type_choice
        while true; do
            read -p "选择: " type_choice
            [[ "$type_choice" =~ ^[0-2]$ ]] && break || echo -e "${RED}无效选择${NC}"
        done
        [ "$type_choice" -eq 0 ] && return 1
        [ "$type_choice" -eq 2 ] && part_type="logical"
    fi

    echo -e "${YELLOW}请输入分区大小（例如 10G、500M，或 50%）：${NC}"
    read -p "大小: " part_size
    [ -z "$part_size" ] && { echo -e "${RED}大小不能为空${NC}"; return 1; }

    local start="0%"
    if [[ "$part_size" == *% ]]; then
        end="$part_size"
        parted -s "$disk" mkpart "$part_type" "$start" "$end"
    else
        parted -s "$disk" mkpart "$part_type" "$start" "$part_size"
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}分区创建成功${NC}"
        reload_partition_table "$disk"
    else
        echo -e "${RED}分区创建失败${NC}"
        return 1
    fi
}

delete_partition() {
    echo -e "${YELLOW}===== 删除分区 =====${NC}"
    select_disk_for_partition || return 1
    local disk="$selected_disk"

    local parts=()
    while IFS= read -r line; do
        parts+=("$line")
    done < <(lsblk -n -o NAME,SIZE "$disk" | grep 'part' | awk '{print "/dev/"$1" "$2}')

    [ ${#parts[@]} -eq 0 ] && { echo -e "${RED}磁盘上没有分区${NC}"; return 1; }

    echo -e "${YELLOW}请选择要删除的分区（可多选，逗号分隔）：${NC}"
    local i=1
    for p in "${parts[@]}"; do
        echo "  $i) $p"
        ((i++))
    done
    echo "  0) 返回上级菜单（默认）"

    local input
    read -p "选择: " input
    [ -z "$input" ] || [ "$input" = "0" ] && return 1

    parse_choices "$input" || { echo -e "${RED}无效输入${NC}"; return 1; }

    local selected_parts=()
    for num in "${SELECTED_INDICES[@]}"; do
        if [ "$num" -ge 1 ] && [ "$num" -le ${#parts[@]} ]; then
            selected_parts+=("${parts[$((num-1))]%% *}")
        else
            echo -e "${RED}编号 $num 超出范围，已忽略${NC}"
        fi
    done

    [ ${#selected_parts[@]} -eq 0 ] && { echo -e "${RED}没有有效的分区被选择${NC}"; return 1; }

    echo -e "${YELLOW}以下分区将被删除：${NC}"
    printf '%s\n' "${selected_parts[@]}"
    read -p "警告：删除分区将导致数据丢失！确认？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    for part in "${selected_parts[@]}"; do
        if mount | grep -q "$part"; then
            echo -e "${YELLOW}分区 $part 已挂载，尝试卸载...${NC}"
            umount "$part" || { echo -e "${RED}卸载失败，跳过删除${NC}"; continue; }
        fi
        local part_num=$(echo "$part" | grep -o '[0-9]*$')
        local disk_name=$(echo "$part" | sed 's/[0-9]*$//')
        parted -s "$disk_name" rm "$part_num" && echo -e "${GREEN}分区 $part 已删除${NC}" || echo -e "${RED}删除分区 $part 失败${NC}"
    done
    reload_partition_table "$disk"
}

format_partition() {
    echo -e "${YELLOW}===== 格式化分区 =====${NC}"
    list_all_partitions

    echo -e "${YELLOW}请选择要格式化的分区（输入设备路径，例如 /dev/sdb1）：${NC}"
    read -p "设备路径: " part
    [ -z "$part" ] || [ ! -b "$part" ] && { echo -e "${RED}无效的设备路径${NC}"; return 1; }

    mount | grep -q "$part" && { echo -e "${RED}错误：$part 已挂载，请先卸载${NC}"; return 1; }

    echo -e "${YELLOW}请选择文件系统类型：${NC}"
    echo "  1) ext4"
    echo "  2) xfs"
    echo "  0) 返回上级菜单（默认）"
    local fs_choice
    while true; do
        read -p "选择: " fs_choice
        [[ "$fs_choice" =~ ^[0-2]$ ]] && break || echo -e "${RED}无效选择${NC}"
    done
    [ "$fs_choice" -eq 0 ] && return 1

    local fs_type
    [ "$fs_choice" -eq 1 ] && fs_type="ext4" || fs_type="xfs"

    read -p "警告：格式化将擦除 $part 上的所有数据！确认？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo "操作已取消"; return 1; }

    echo -e "${GREEN}正在格式化 $part 为 $fs_type ...${NC}"
    if [ "$fs_type" = "ext4" ]; then
        mkfs.ext4 "$part"
    else
        mkfs.xfs -f "$part"
    fi
    [ $? -eq 0 ] && echo -e "${GREEN}格式化成功${NC}" || { echo -e "${RED}格式化失败${NC}"; return 1; }
}

mount_partition() {
    echo -e "${YELLOW}===== 挂载分区 =====${NC}"
    echo -e "${YELLOW}未挂载的分区：${NC}"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | awk '$4 == "" && $3 != "" {print "/dev/"$1"  "$2"  "$3}'

    read -p "请输入要挂载的分区（例如 /dev/sdb1）: " part
    [ -z "$part" ] || [ ! -b "$part" ] && { echo -e "${RED}无效的设备路径${NC}"; return 1; }
    mount | grep -q "$part" && { echo -e "${RED}错误：$part 已挂载${NC}"; return 1; }

    read -p "请输入挂载点（例如 /mnt/data）: " mountpoint
    [ -z "$mountpoint" ] && { echo -e "${RED}挂载点不能为空${NC}"; return 1; }
    [ ! -d "$mountpoint" ] && mkdir -p "$mountpoint" && echo -e "${GREEN}创建挂载点目录 $mountpoint${NC}"

    mount "$part" "$mountpoint" && echo -e "${GREEN}挂载成功！${NC}" || { echo -e "${RED}挂载失败${NC}"; return 1; }

    read -p "是否将挂载信息写入 /etc/fstab？(y/N): " add_fstab
    if [[ "$add_fstab" =~ ^[Yy]$ ]]; then
        local uuid=$(blkid -s UUID -o value "$part")
        local fs_type=$(blkid -s TYPE -o value "$part")
        if [ -n "$uuid" ] && [ -n "$fs_type" ]; then
            echo "UUID=$uuid $mountpoint $fs_type defaults 0 2" >> /etc/fstab
            echo -e "${GREEN}已添加到 /etc/fstab${NC}"
        else
            echo -e "${YELLOW}无法获取 UUID 或文件系统类型，请手动添加${NC}"
        fi
    fi
}

umount_partition() {
    echo -e "${YELLOW}===== 卸载分区 =====${NC}"
    echo -e "${YELLOW}当前已挂载的分区（非系统）：${NC}"
    mount | grep -E '/dev/sd|/dev/nvme|/dev/mapper' | awk '{print $1"  "$3}'

    read -p "请输入要卸载的分区或挂载点（例如 /dev/sdb1 或 /mnt/data）: " target
    [ -z "$target" ] && { echo -e "${RED}输入不能为空${NC}"; return 1; }

    umount "$target" && echo -e "${GREEN}卸载成功${NC}" || { echo -e "${RED}卸载失败${NC}"; return 1; }
}

disk_management_menu() {
    while true; do
        echo ""
        echo -e "${GREEN}========== 磁盘管理 ==========${NC}"
        echo "  1) 显示磁盘详细信息"
        echo "  2) 创建分区"
        echo "  3) 删除分区"
        echo "  4) 格式化分区"
        echo "  5) 挂载分区"
        echo "  6) 卸载分区"
        echo "  0) 返回主菜单"
        echo -e "${GREEN}==============================${NC}"
        read -p "请选择操作: " choice
        case "$choice" in
            1) show_disk_details ;;
            2) create_partition_manual ;;
            3) delete_partition ;;
            4) format_partition ;;
            5) mount_partition ;;
            6) umount_partition ;;
            0) return ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
    done
}

# ============================================================
# 主菜单
# ============================================================
main_menu() {
    while true; do
        echo ""
        echo -e "${GREEN}========== LVM + 磁盘管理脚本（全面增强版） ==========${NC}"
        echo "  1) 显示当前 LVM 状态"
        echo "  2) 创建物理卷 (PV)"
        echo "  3) 创建卷组 (VG)          [支持多选 PV]"
        echo "  4) 创建逻辑卷 (LV)"
        echo "  5) 格式化并挂载逻辑卷"
        echo "  6) 扩展逻辑卷 (LV)"
        echo "  7) 删除逻辑卷 (LV)        [支持多选]"
        echo "  8) 删除卷组 (VG)          [支持多选]"
        echo "  9) 删除物理卷 (PV)        [支持多选]"
        echo " 10) 扩展卷组 (添加 PV)"
        echo " 11) 缩减卷组 (移除 PV)"
        echo " 12) 创建 LV 快照"
        echo " 13) 信息查询"
        echo " 14) 磁盘管理"
        echo "  0) 退出"
        echo -e "${GREEN}=======================================================${NC}"
        read -p "请选择操作: " choice
        case "$choice" in
            1) show_status ;;
            2) create_pv ;;
            3) create_vg ;;
            4) create_lv ;;
            5) format_and_mount_lv ;;
            6) extend_lv ;;
            7) delete_lv ;;
            8) delete_vg ;;
            9) delete_pv ;;
            10) extend_vg ;;
            11) reduce_vg ;;
            12) create_lv_snapshot ;;
            13) info_menu ;;
            14) disk_management_menu ;;
            0) echo "退出"; exit 0 ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
    done
}

# ---------- 主程序 ----------
detect_os
check_root
check_deps
main_menu