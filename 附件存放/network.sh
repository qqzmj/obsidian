#!/usr/bin/env bash
# ============================================================================
#  network-config.sh  Server Network Management Script  v3.2-en
#
#  Modules:
#    [1] Configure Network IP  - static IP + exclusive service selection
#        (network service / NetworkManager, the other is disabled)
#    [2] Backup / Restore      - archive / list / restore / delete configs
#    [3] Interface Manage      - status / up / down / activate / diagnose
#    [4] Add / Delete NIC config (per selected backend)
#
#  Supported systems:
#    RHEL family (CentOS/Rocky/Alma/Fedora): /etc/sysconfig/network-scripts/ifcfg-*
#    Debian classic ifupdown:               /etc/network/interfaces.d/* + networking
#    Ubuntu/Debian + netplan:               /etc/netplan/*.yaml + netplan apply
#    DNS: systemd-resolved / resolv.conf
#    NetworkManager detection: systemd unit + nmcli cmd + package (3-way)
#
#  Usage:  sudo bash network-config.sh
#
#  NOTE: All output is ASCII/English so it renders on any terminal.
# ============================================================================

set -u

# ---------- terminal colors (ANSI is widely supported) ----------
if [ -t 1 ]; then
    R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; BD=$'\033[1m'; N=$'\033[0m'
else
    R=""; G=""; Y=""; BD=""; N=""
fi

info(){ echo "${G}[INFO]${N} $*"; }
warn(){ echo "${Y}[WARN]${N} $*"; }
err(){  echo "${R}[ERROR]${N} $*" >&2; }
die(){  err "$*"; exit 1; }

confirm(){
    local a
    read -r -p "$1 [y/N]: " a
    [[ "${a,,}" == "y" || "${a,,}" == "yes" ]]
}

warn_ssh(){
    if [ -n "${SSH_CONNECTION:-}" ]; then
        warn "This is a remote SSH session; changing this NIC may drop the connection."
    fi
}

# ---------- IP / mask helpers ----------
valid_ip(){
    local ip=$1 p
    local -a parts=()
    IFS=. read -r -a parts <<< "$ip"
    (( ${#parts[@]} == 4 )) || return 1
    for p in "${parts[@]}"; do
        [[ "$p" =~ ^[0-9]+$ ]] || return 1
        (( p >= 0 && p <= 255 )) || return 1
    done
    return 0
}

mask_to_cidr(){
    local mask=$1 val=0 oct
    IFS=. read -r -a parts <<< "$mask"
    for oct in "${parts[@]}"; do
        case $oct in
            255) val=$((val+8));; 254) val=$((val+7));; 252) val=$((val+6));;
            248) val=$((val+5));; 240) val=$((val+4));; 224) val=$((val+3));;
            192) val=$((val+2));; 128) val=$((val+1));; 0) ;;
            *) return 1;;
        esac
    done
    echo "$val"
}

cidr_to_mask(){
    local cidr=$1 mask=""
    for ((i=0;i<4;i++)); do
        if (( cidr >= 8 )); then mask+="255."; cidr=$((cidr-8))
        elif (( cidr > 0 )); then mask+="$((256 - 2**(8-cidr)))."; cidr=0
        else mask+="0."
        fi
    done
    echo "${mask%.}"
}

get_prefix(){
    local input=$1 cidr
    [[ "$input" =~ ^/ ]] && input="${input#/}"
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        (( 10#$input >= 0 && 10#$input <= 32 )) || return 1
        echo "$((10#$input))"; return 0
    fi
    valid_ip "$input" || return 1
    cidr=$(mask_to_cidr "$input") || return 1
    echo "$cidr"
}

# ---------- service helpers ----------
unit_exists(){ systemctl list-unit-files "$1.service" 2>/dev/null | grep -q "^$1.service"; }

disable_unit(){
    local u=$1
    unit_exists "$u" || return 0
    systemctl is-active "$u" >/dev/null 2>&1 && {
        info "Stopping $u.service ..."
        systemctl stop "$u" >/dev/null 2>&1
    }
    info "Disabling $u.service (no autostart) ..."
    systemctl disable "$u" >/dev/null 2>&1 || true
}

enable_unit(){
    local u=$1 s
    s=$(systemctl is-enabled "$u" 2>/dev/null || true)
    [ "$s" = "masked" ] && { info "Unmasking $u ..."; systemctl unmask "$u" >/dev/null 2>&1; }
    info "Enabling + starting $u.service ..."
    systemctl enable --now "$u" >/dev/null 2>&1 || die "$u.service failed to start"
}

# ---------- system detection ----------
OS_ID=""; OS_NAME=""; OS_FAMILY=""
detect_os_family(){
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID:-}"; OS_NAME="${PRETTY_NAME:-$NAME $VERSION}"
    fi
    case "$OS_ID" in
        rhel|centos|rocky|alma|fedora|ol|amzn|scientific) OS_FAMILY="rhel" ;;
        debian|ubuntu|raspbian|linuxmint|pop)             OS_FAMILY="debian" ;;
        *) OS_FAMILY="other" ;;
    esac
}

detect_system(){
    detect_os_family
    echo "============================================================"
    echo "  System Information"
    echo "============================================================"
    echo "  Distribution : $OS_NAME"
    echo "  ID           : ${OS_ID:-unknown}  (family: $OS_FAMILY)"
    echo "  Kernel       : $(uname -r)"
    [ -d /run/systemd/system ] || die "Only systemd-based systems are supported."
    echo "  Init         : systemd"
    echo
}

# ---------- NetworkManager detection (3-way) ----------
NM_DETECTED=0
detect_nm(){
    if unit_exists NetworkManager; then
        info "    [OK] NetworkManager.service unit exists"
        NM_DETECTED=1
    fi
    if command -v nmcli >/dev/null 2>&1; then
        info "    [OK] nmcli command available ($(nmcli --version 2>/dev/null | head -1))"
        NM_DETECTED=1
    fi
    local pkg=""
    if command -v dpkg >/dev/null 2>&1 && dpkg -s network-manager >/dev/null 2>&1; then
        pkg="network-manager"
    elif command -v rpm >/dev/null 2>&1 && rpm -q NetworkManager >/dev/null 2>&1; then
        pkg="NetworkManager"
    fi
    [ -n "$pkg" ] && { info "    [OK] package installed: $pkg"; NM_DETECTED=1; }
    [ $NM_DETECTED -eq 1 ]
}

find_net_unit(){
    unit_exists network    && { echo network; return; }
    unit_exists networking && { echo networking; return; }
    echo ""
}

# ---------- netplan detection ----------
netplan_files_exist(){
    command -v netplan >/dev/null 2>&1 || return 1
    compgen -G "/etc/netplan/*.yaml" >/dev/null 2>&1 || return 1
    return 0
}

netplan_active(){
    netplan_files_exist || return 1
    [ "$OS_ID" = "ubuntu" ] && return 0
    systemctl is-active networking >/dev/null 2>&1 && return 1
    return 0
}

# ---------- interface helpers ----------
list_interfaces(){
    local dev
    for dev in /sys/class/net/*; do
        dev=$(basename "$dev")
        [ "$dev" = "lo" ] && continue
        case "$dev" in
            veth*|docker*|br-*|virbr*|tap*|tun*|bond*|dummy*|vnet*|wg*) continue;;
        esac
        echo "$dev"
    done
}

choose_interface(){
    local -a ifaces=()
    local i=1 n dev mac ip
    mapfile -t ifaces < <(list_interfaces)
    [ ${#ifaces[@]} -gt 0 ] || die "No usable physical NIC detected."
    echo "------------------------------------------------------------"
    echo "  Detected physical NICs:"
    for dev in "${ifaces[@]}"; do
        mac=$(cat "/sys/class/net/$dev/address" 2>/dev/null)
        ip=$(ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{print $4}' | head -1)
        printf '    [%d] %-12s MAC=%s IP=%s\n' "$i" "$dev" "${mac:-unknown}" "${ip:-none}"
        ((i++))
    done
    echo "------------------------------------------------------------"
    while :; do
        read -r -p "Select NIC number [1-${#ifaces[@]}]: " n
        if [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n >= 1 && 10#$n <= ${#ifaces[@]} )); then
            IFACE="${ifaces[$((10#$n - 1))]}"
            info "Selected NIC: $IFACE"
            return 0
        fi
        warn "Invalid input, try again."
    done
}

list_iface_configs(){
    local dev has
    for dev in $(list_interfaces); do
        has=""
        [ -f "/etc/sysconfig/network-scripts/ifcfg-$dev" ] && has=1
        [ -f "/etc/network/interfaces.d/$dev" ] && has=1
        grep -q "^iface $dev inet" /etc/network/interfaces 2>/dev/null && has=1
        command -v nmcli >/dev/null 2>&1 && \
            nmcli -t -f DEVICE con show 2>/dev/null | grep -qx "$dev" && has=1
        for f in /etc/netplan/*.yaml; do
            grep -q "^  $dev:" "$f" 2>/dev/null && { has=1; break; }
        done
        [ -n "$has" ] && echo "$dev"
    done
}

# ---------- collect parameters ----------
collect_params(){
    echo
    echo "============================================================"
    echo "  Configure network parameters ($IFACE)"
    echo "============================================================"
    while :; do
        read -r -p "IP address (e.g. 192.168.1.100): " IP_ADDR
        valid_ip "$IP_ADDR" && break
        warn "Invalid IP format, try again."
    done
    while :; do
        read -r -p "Netmask (e.g. 255.255.255.0 or /24): " MASK_INPUT
        if CIDR=$(get_prefix "$MASK_INPUT"); then
            NETMASK_DOTTED=$(cidr_to_mask "$CIDR")
            break
        fi
        warn "Invalid netmask, try again."
    done
    while :; do
        read -r -p "Gateway (e.g. 192.168.1.1, Enter to skip): " GATEWAY
        [ -z "$GATEWAY" ] && { GATEWAY=""; break; }
        valid_ip "$GATEWAY" && break
        warn "Invalid gateway, try again."
    done
    while :; do
        read -r -p "Primary DNS (e.g. 114.114.114.114): " DNS1
        valid_ip "$DNS1" && break
        warn "Invalid DNS, try again."
    done
    read -r -p "Secondary DNS (Enter = same as primary): " DNS2
    valid_ip "$DNS2" 2>/dev/null || DNS2="$DNS1"
}

# ---------- config writers (3 backends) ----------
write_network_rhel(){
    local conf="/etc/sysconfig/network-scripts/ifcfg-$IFACE"
    [ -f "$conf" ] && cp "$conf" "$conf.bak.$(date +%F_%T)"
    cat > "$conf" <<EOF
TYPE=Ethernet
BOOTPROTO=static
DEFROUTE=yes
NAME=$IFACE
DEVICE=$IFACE
ONBOOT=yes
NM_CONTROLLED=no
IPADDR=$IP_ADDR
NETMASK=$NETMASK_DOTTED
GATEWAY=$GATEWAY
DNS1=$DNS1
DNS2=$DNS2
EOF
    info "Written $conf"
}

write_network_debian(){
    local conf="/etc/network/interfaces.d/$IFACE"
    mkdir -p /etc/network/interfaces.d
    if ! grep -q "interfaces.d" /etc/network/interfaces 2>/dev/null; then
        [ -f /etc/network/interfaces ] && cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%F_%T) 2>/dev/null
        echo "source /etc/network/interfaces.d/*" >> /etc/network/interfaces
    fi
    [ -f "$conf" ] && cp "$conf" "$conf.bak.$(date +%F_%T)"
    cat > "$conf" <<EOF
auto $IFACE
iface $IFACE inet static
    address $IP_ADDR
    netmask $NETMASK_DOTTED
    gateway $GATEWAY
    dns-nameservers $DNS1 $DNS2
EOF
    info "Written $conf"
}

write_netplan_conf(){
    local netplan_file="/etc/netplan/99-custom-$IFACE.yaml"
    [ -f "$netplan_file" ] && cp "$netplan_file" "$netplan_file.bak.$(date +%F_%T)"
    cat > "$netplan_file" <<EOF
network:
  version: 2
  ethernets:
    $IFACE:
      renderer: networkd
      dhcp4: no
      addresses:
        - $IP_ADDR/$CIDR
EOF
    if [ -n "$GATEWAY" ]; then
        cat >> "$netplan_file" <<EOF
      routes:
        - to: default
          via: $GATEWAY
EOF
    fi
    cat >> "$netplan_file" <<EOF
      nameservers:
        addresses:
          - $DNS1
          - $DNS2
EOF
    info "Written netplan config: $netplan_file"
}

write_nmcli(){
    CUR_CONN=$(nmcli -t -f NAME,DEVICE con show 2>/dev/null | awk -F: -v d="$IFACE" '$2==d {print $1; exit}')
    if [ -z "$CUR_CONN" ]; then
        CUR_CONN="static-$IFACE"
        info "No existing connection for $IFACE, creating new one: $CUR_CONN"
        nmcli con add type ethernet con-name "$CUR_CONN" ifname "$IFACE" \
            ipv4.method manual \
            ipv4.addresses "${IP_ADDR}/${CIDR}" \
            ipv4.gateway "$GATEWAY" \
            ipv4.dns "$DNS1 $DNS2" \
            connection.autoconnect yes || die "nmcli failed to create connection"
    else
        info "Using existing connection: $CUR_CONN"
        nmcli con mod "$CUR_CONN" \
            ipv4.method manual \
            ipv4.addresses "${IP_ADDR}/${CIDR}" \
            ipv4.gateway "$GATEWAY" \
            ipv4.dns "$DNS1 $DNS2" \
            connection.autoconnect yes || die "nmcli failed to modify connection"
    fi
}

apply_dns(){
    if command -v resolvectl >/dev/null 2>&1 && systemctl is-active systemd-resolved >/dev/null 2>&1; then
        resolvectl dns "$IFACE" "$DNS1" "$DNS2" >/dev/null 2>&1 && info "DNS set via systemd-resolved for $IFACE"
        resolvectl domain "$IFACE" "" >/dev/null 2>&1
        return 0
    fi
    if [ -f /etc/resolv.conf ] && [ ! -L /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%F_%T) 2>/dev/null
        {
            echo "# Generated by network-config.sh $(date)"
            echo "nameserver $DNS1"
            [ "$DNS1" != "$DNS2" ] && echo "nameserver $DNS2"
        } > /etc/resolv.conf
        info "Written /etc/resolv.conf"
    fi
}

apply_static_config(){
    local method=$1 net_unit=$2
    if [ "$method" = "NetworkManager" ]; then
        disable_unit network
        disable_unit networking
        disable_unit systemd-networkd
        enable_unit NetworkManager
        write_nmcli
        info "Restarting NetworkManager to apply ..."
        systemctl restart NetworkManager >/dev/null 2>&1 || die "NetworkManager restart failed"
        nmcli con up "$CUR_CONN" >/dev/null 2>&1 || warn "nmcli connection activation failed, check config."
        netplan_files_exist && warn "Configs remain in /etc/netplan; remove them to avoid boot conflicts with NetworkManager."
    else
        disable_unit NetworkManager
        case "$OS_FAMILY" in
            rhel)
                write_network_rhel
                enable_unit "$net_unit"
                info "Restarting $net_unit to apply ..."
                systemctl restart "$net_unit" >/dev/null 2>&1 || die "$net_unit restart failed"
                ;;
            debian)
                if netplan_active; then
                    write_netplan_conf
                    enable_unit systemd-networkd
                    disable_unit networking
                    info "Running netplan apply ..."
                    netplan apply || die "netplan apply failed"
                else
                    write_network_debian
                    disable_unit systemd-networkd
                    enable_unit networking
                    info "Restarting networking to apply ..."
                    systemctl restart networking >/dev/null 2>&1 || die "networking restart failed"
                fi
                ;;
            *)
                warn "Unknown OS family, falling back to RHEL style."
                write_network_rhel
                enable_unit "$net_unit"
                systemctl restart "$net_unit" >/dev/null 2>&1 || die "$net_unit restart failed"
                ;;
        esac
    fi
    sleep 2
    apply_dns
}

# ============================================================================
#  [1] Configure network IP
# ============================================================================
menu_configure(){
    local net_unit sel svc_desc
    echo
    echo "============================================================"
    echo "  Configure Network IP (exclusive service selection)"
    echo "============================================================"
    choose_interface
    echo
    echo "  Available network services:"
    unit_exists network    && echo "    [OK] network.service      (traditional / RHEL family)"
    unit_exists networking && echo "    [OK] networking.service   (traditional / Debian family)"
    detect_nm
    [ "$OS_FAMILY" = "debian" ] && netplan_active && echo "    [OK] netplan (renderer=networkd)"
    echo
    net_unit=$(find_net_unit)
    echo "------------------------------------------------------------"
    echo "   [1] network service  (traditional, edit config files)"
    [ -n "$net_unit" ] && echo "       service unit: $net_unit.service" || warn "       no traditional network unit found"
    echo "   [2] NetworkManager   (modern, managed by nmcli)"
    [ $NM_DETECTED -eq 0 ] && warn "       NetworkManager not detected"
    echo "   [0] Back"
    echo "------------------------------------------------------------"
    while :; do
        read -r -p "Select [0-2]: " sel
        case $sel in
            1) [ -n "$net_unit" ] || { warn "Traditional network service unavailable, choose again."; continue; }
               svc_desc="$net_unit.service";;
            2) command -v nmcli >/dev/null || { warn "nmcli not found, choose again."; continue; }
               svc_desc="NetworkManager (nmcli)";;
            0) return 0;;
            *) warn "Invalid input, try again."; continue;;
        esac
        break
    done

    collect_params
    [ "$OS_FAMILY" = "debian" ] && netplan_active && svc_desc="netplan (renderer=networkd)"
    echo
    echo "============================================================"
    echo "  Confirm configuration"
    echo "============================================================"
    echo "  NIC        : $IFACE"
    echo "  Service    : $svc_desc"
    echo "  IP/Netmask : $IP_ADDR / $NETMASK_DOTTED (/$CIDR)"
    echo "  Gateway    : ${GATEWAY:-<none>}"
    echo "  DNS        : $DNS1 $DNS2"
    echo "------------------------------------------------------------"
    confirm "Apply this configuration?" || { echo "Cancelled."; return 0; }

    if [ "$sel" = "2" ]; then
        apply_static_config "NetworkManager" ""
    else
        apply_static_config "network" "$net_unit"
    fi
    verify_and_test
}

verify_and_test(){
    local cur
    cur=$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | grep -F "$IP_ADDR" || true)
    [ -n "$cur" ] && info "OK: config applied, $IFACE = $IP_ADDR/$CIDR" \
                  || warn "NOT detected $IP_ADDR on $IFACE, please check config."
    echo
    confirm "Test connectivity now?" || { info "Skipped connectivity test."; return 0; }
    test_connectivity
}

# ============================================================================
#  [2] Backup / Restore
# ============================================================================
BACKUP_DIR="/var/backups/network-config"

do_backup(){
    local ts bdir
    ts=$(date +%Y%m%d_%H%M%S)
    bdir="$BACKUP_DIR/$ts"
    mkdir -p "$bdir"
    info "Backing up to $bdir ..."
    [ -d /etc/sysconfig/network-scripts ] && { cp -a /etc/sysconfig/network-scripts "$bdir/rhel-network-scripts" 2>/dev/null; info "  - backed up RHEL ifcfg configs"; }
    [ -d /etc/netplan ] && { cp -a /etc/netplan "$bdir/netplan" 2>/dev/null; info "  - backed up netplan configs"; }
    [ -d /etc/network ] && { cp -a /etc/network "$bdir/etc-network" 2>/dev/null; info "  - backed up /etc/network"; }
    [ -f /etc/resolv.conf ] && { cp -a /etc/resolv.conf "$bdir/resolv.conf" 2>/dev/null; info "  - backed up resolv.conf"; }
    [ -d /etc/NetworkManager/system-connections ] && { cp -a /etc/NetworkManager/system-connections "$bdir/nm-connections" 2>/dev/null; info "  - backed up NetworkManager connections"; }
    [ -f /etc/hostname ] && cp -a /etc/hostname "$bdir/hostname" 2>/dev/null
    [ -f /etc/hosts ] && cp -a /etc/hosts "$bdir/hosts" 2>/dev/null
    {
        echo "OS_ID=$OS_ID"
        echo "OS_FAMILY=$OS_FAMILY"
        systemctl is-active NetworkManager >/dev/null 2>&1 && echo "NM_ACTIVE=1"
        systemctl is-active network >/dev/null 2>&1 && echo "NETWORK_ACTIVE=1"
        systemctl is-active networking >/dev/null 2>&1 && echo "NETWORKING_ACTIVE=1"
        systemctl is-active systemd-networkd >/dev/null 2>&1 && echo "NETWORKD_ACTIVE=1"
    } > "$bdir/state.txt"
    du -sh "$bdir" | awk '{print "  Backup size: "$1}'
    info "Backup complete: $bdir"
}

do_restore(){
    local -a snaps=()
    local i=0 n bdir
    mapfile -t snaps < <(ls -1 "$BACKUP_DIR" 2>/dev/null | sort -r)
    [ ${#snaps[@]} -gt 0 ] || { warn "No backups available."; return 0; }
    echo "Available backups (newest first):"
    for ((i=0;i<${#snaps[@]};i++)); do
        printf '  [%d] %s  (%s)\n' "$((i+1))" "${snaps[i]}" \
            "$(du -sh "$BACKUP_DIR/${snaps[i]}" 2>/dev/null | cut -f1)"
    done
    while :; do
        read -r -p "Select backup to restore [1-${#snaps[@]}]: " n
        [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n >= 1 && 10#$n <= ${#snaps[@]} )) && break
        warn "Invalid input."
    done
    bdir="$BACKUP_DIR/${snaps[$((10#$n - 1))]}"
    echo
    warn "Restore will OVERWRITE all current network configs and restart services!"
    confirm "Confirm restore this backup?" || { echo "Cancelled."; return 0; }

    info "Stopping current network services ..."
    systemctl stop NetworkManager networking network systemd-networkd 2>/dev/null

    [ -d "$bdir/rhel-network-scripts" ] && { rm -rf /etc/sysconfig/network-scripts; mkdir -p /etc/sysconfig; cp -a "$bdir/rhel-network-scripts" /etc/sysconfig/network-scripts; info "Restored RHEL ifcfg configs"; }
    [ -d "$bdir/netplan" ] && { rm -rf /etc/netplan; cp -a "$bdir/netplan" /etc/netplan; info "Restored netplan configs"; }
    [ -d "$bdir/etc-network" ] && { rm -rf /etc/network; cp -a "$bdir/etc-network" /etc/network; info "Restored /etc/network"; }
    [ -d "$bdir/nm-connections" ] && { rm -rf /etc/NetworkManager/system-connections; mkdir -p /etc/NetworkManager; cp -a "$bdir/nm-connections" /etc/NetworkManager/system-connections; info "Restored NetworkManager connections"; }
    [ -f "$bdir/resolv.conf" ] && { rm -f /etc/resolv.conf; cp -a "$bdir/resolv.conf" /etc/resolv.conf; info "Restored resolv.conf"; }
    [ -f "$bdir/hostname" ] && cp -a "$bdir/hostname" /etc/hostname 2>/dev/null
    [ -f "$bdir/hosts" ] && cp -a "$bdir/hosts" /etc/hosts 2>/dev/null

    info "Restarting services per backup state ..."
    local NM_ACTIVE=0 NETWORK_ACTIVE=0 NETWORKING_ACTIVE=0 NETWORKD_ACTIVE=0
    [ -f "$bdir/state.txt" ] && . "$bdir/state.txt"
    [ $NETWORK_ACTIVE -eq 1 ] && enable_unit network
    [ $NETWORKING_ACTIVE -eq 1 ] && enable_unit networking
    [ $NETWORKD_ACTIVE -eq 1 ] && enable_unit systemd-networkd
    [ $NM_ACTIVE -eq 1 ] && enable_unit NetworkManager
    netplan_files_exist && command -v netplan >/dev/null 2>&1 && { info "Running netplan apply ..."; netplan apply 2>/dev/null || true; }
    info "Restore complete."
}

do_del_backup(){
    local -a snaps=()
    local i=0 n
    mapfile -t snaps < <(ls -1 "$BACKUP_DIR" 2>/dev/null | sort -r)
    [ ${#snaps[@]} -gt 0 ] || { warn "No backups available."; return 0; }
    echo "Available backups (newest first):"
    for ((i=0;i<${#snaps[@]};i++)); do
        printf '  [%d] %s  (%s)\n' "$((i+1))" "${snaps[i]}" \
            "$(du -sh "$BACKUP_DIR/${snaps[i]}" 2>/dev/null | cut -f1)"
    done
    read -r -p "Select backup to delete [0=cancel]: " n
    [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n >= 1 && 10#$n <= ${#snaps[@]} )) || { echo "Cancelled."; return 0; }
    confirm "Confirm delete this backup?" && { rm -rf "$BACKUP_DIR/${snaps[$((10#$n - 1))]}"; info "Backup deleted."; }
}

menu_backup(){
    while :; do
        echo
        echo "============================================================"
        echo "  Backup / Restore Network Config"
        echo "============================================================"
        echo "   [1] Create backup"
        echo "   [2] List backups"
        echo "   [3] Restore backup"
        echo "   [4] Delete backup"
        echo "   [0] Back to main menu"
        local opt
        read -r -p "Select [0-4]: " opt
        case $opt in
            1) do_backup ;;
            2) ls -1 "$BACKUP_DIR" 2>/dev/null | sort -r | sed 's/^/    - /' | head -20 \
                 || warn "No backups available.";;
            3) do_restore ;;
            4) do_del_backup ;;
            0) return 0 ;;
            *) warn "Invalid input." ;;
        esac
    done
}

# ============================================================================
#  [3] Interface manage (status/up/down/activate/diagnose)
# ============================================================================
menu_iface_manage(){
    while :; do
        echo
        echo "============================================================"
        echo "  Interface Management"
        echo "============================================================"
        echo "   [1] Show interface status"
        echo "   [2] Enable NIC (ip link up)"
        echo "   [3] Disable NIC (ip link down)"
        echo "   [4] Activate NIC connection"
        echo "   [5] Diagnose NIC"
        echo "   [0] Back to main menu"
        local opt
        read -r -p "Select [0-5]: " opt
        case $opt in
            0) return 0 ;;
            1) echo; ip -br link show; echo; ip -br addr show; echo; ip route; echo; continue ;;
            2|3)
                choose_interface || continue
                warn_ssh
                confirm "Confirm '$([ "$opt" = "2" ] && echo up || echo down)' on NIC $IFACE?" || continue
                if [ "$opt" = "2" ]; then
                    ip link set dev "$IFACE" up && info "NIC $IFACE is up" || warn "Failed to bring up"
                else
                    ip link set dev "$IFACE" down && info "NIC $IFACE is down" || warn "Failed to bring down"
                fi
                ;;
            4)
                choose_interface || continue
                warn_ssh
                activate_iface "$IFACE"
                ;;
            5)
                choose_interface || continue
                diag_iface "$IFACE"
                ;;
            *) warn "Invalid input." ;;
        esac
    done
}

activate_iface(){
    local dev=$1 conn=""
    if unit_exists NetworkManager && systemctl is-active NetworkManager >/dev/null 2>&1; then
        conn=$(nmcli -t -f NAME,DEVICE con show 2>/dev/null | awk -F: -v d="$dev" '$2==d {print $1; exit}')
        if [ -n "$conn" ]; then
            nmcli con up "$conn" && info "OK: NM connection activated: $conn"
        else
            warn "NetworkManager has no connection for $dev, using ip link up"
            ip link set dev "$dev" up && info "OK: NIC $dev is up"
        fi
    else
        if command -v ifup >/dev/null 2>&1; then
            ifup "$dev" && info "OK: $dev activated via ifup" || { ip link set dev "$dev" up && info "OK: NIC $dev is up"; }
        else
            ip link set dev "$dev" up && info "OK: NIC $dev is up"
        fi
    fi
}

diag_iface(){
    local dev=$1 gw
    echo
    echo "=================== Diagnose $dev ==================="
    echo "--- Interface state ---"
    ip -br link show dev "$dev"
    echo
    echo "--- IPv4 address ---"
    ip -4 -o addr show dev "$dev" || echo "  (no IPv4 configured)"
    echo
    echo "--- Routes ---"
    ip route show dev "$dev" || echo "  (no routes)"
    echo
    echo "--- DNS ---"
    grep -E "^\s*nameserver" /etc/resolv.conf 2>/dev/null | sed 's/^/  /' || echo "  (none)"
    echo
    echo "--- Manager ---"
    if systemctl is-active NetworkManager >/dev/null 2>&1; then
        nmcli dev status 2>/dev/null | grep -E "^(DEVICE|$dev)\b" || echo "  NM does not manage $dev"
    elif systemctl is-active systemd-networkd >/dev/null 2>&1; then
        echo "  managed by systemd-networkd"
    elif systemctl is-active networking >/dev/null 2>&1 || systemctl is-active network >/dev/null 2>&1; then
        echo "  managed by traditional network/networking service"
    else
        echo "  no network manager active"
    fi
    echo
    echo "--- Connectivity ---"
    gw=$(ip route show dev "$dev" | awk '/^default/{print $3; exit}')
    if [ -n "$gw" ]; then
        echo "  ping gateway $gw ..."
        ping -c 2 -W 2 "$gw" >/dev/null 2>&1 && echo "    [OK] gateway reachable" || echo "    [X] gateway unreachable"
    else
        echo "  no default gateway for $dev"
    fi
    echo "  ping public 223.5.5.5 ..."
    ping -c 2 -W 2 223.5.5.5 >/dev/null 2>&1 && echo "    [OK] public reachable" || echo "    [X] public unreachable (may be ICMP blocked)"
    echo "  DNS resolve www.baidu.com ..."
    getent hosts www.baidu.com >/dev/null 2>&1 && echo "    [OK] DNS works" || echo "    [X] DNS failed"
    echo "=================================================="
}

# ============================================================================
#  [4] Add / Delete NIC config
# ============================================================================
menu_iface_conf(){
    while :; do
        echo
        echo "============================================================"
        echo "  Add / Delete NIC Config"
        echo "============================================================"
        echo "   [1] Add NIC static config"
        echo "   [2] Delete NIC config"
        echo "   [3] Show current configs"
        echo "   [0] Back to main menu"
        local opt
        read -r -p "Select [0-3]: " opt
        case $opt in
            0) return 0 ;;
            1) add_iface_conf ;;
            2) del_iface_conf ;;
            3) show_iface_conf ;;
            *) warn "Invalid input." ;;
        esac
    done
}

add_iface_conf(){
    local sel net_unit
    echo
    echo "Add NIC static config"
    echo "------------------------------------------------------------"
    echo "  Select method:"
    echo "   [1] network service method (ifcfg/interfaces.d/netplan)"
    echo "   [2] NetworkManager method (nmcli)"
    echo "   [0] Cancel"
    while :; do
        read -r -p "Select [0-2]: " sel
        case $sel in
            1) net_unit=$(find_net_unit); [ -n "$net_unit" ] || { warn "No traditional network service, use NetworkManager instead."; continue; }; break;;
            2) command -v nmcli >/dev/null || { warn "nmcli not found."; continue; }; break;;
            0) return 0 ;;
            *) warn "Invalid input." ;;
        esac
    done
    choose_interface || return 0
    collect_params
    echo
    confirm "Add static config for $IFACE with these parameters?" || { echo "Cancelled."; return 0; }
    if [ "$sel" = "2" ]; then
        apply_static_config "NetworkManager" ""
    else
        apply_static_config "network" "$net_unit"
    fi
    info "Config added."
    confirm "Test connectivity?" && test_connectivity
}

del_iface_conf(){
    local -a cfgs=()
    local i=1 n dev
    mapfile -t cfgs < <(list_iface_configs)
    [ ${#cfgs[@]} -gt 0 ] || { warn "No NIC with existing config found."; return 0; }
    echo
    echo "NICs with existing config:"
    for dev in "${cfgs[@]}"; do
        printf '    [%d] %s\n' "$i" "$dev"
        ((i++))
    done
    while :; do
        read -r -p "Select NIC to delete config [0=cancel]: " n
        [[ "$n" =~ ^[0-9]+$ ]] && (( 10#$n >= 1 && 10#$n <= ${#cfgs[@]} )) && { dev="${cfgs[$((10#$n - 1))]}"; break; }
        [ "$n" = "0" ] && return 0
        warn "Invalid input."
    done
    warn_ssh
    confirm "Delete ALL static configs for $dev? (auto backup first)" || { echo "Cancelled."; return 0; }

    if [ -f "/etc/sysconfig/network-scripts/ifcfg-$dev" ]; then
        cp "/etc/sysconfig/network-scripts/ifcfg-$dev" "/etc/sysconfig/network-scripts/ifcfg-$dev.bak.$(date +%F_%T)"
        rm -f "/etc/sysconfig/network-scripts/ifcfg-$dev"
        info "Deleted ifcfg-$dev (backup kept)"
    fi
    if [ -f "/etc/network/interfaces.d/$dev" ]; then
        cp "/etc/network/interfaces.d/$dev" "/etc/network/interfaces.d/$dev.bak.$(date +%F_%T)"
        rm -f "/etc/network/interfaces.d/$dev"
        info "Deleted interfaces.d/$dev (backup kept)"
    fi
    for f in /etc/netplan/*.yaml; do
        if grep -q "^  $dev:" "$f" 2>/dev/null; then
            cp "$f" "$f.bak.$(date +%F_%T)"
            rm -f "$f"
            info "Deleted netplan file $f (backup kept)"
            break
        fi
    done
    if command -v nmcli >/dev/null 2>&1; then
        local conn
        while read -r conn; do
            [ -n "$conn" ] && { nmcli con delete "$conn" && info "Deleted NM connection: $conn"; }
        done < <(nmcli -t -f NAME,DEVICE con show 2>/dev/null | awk -F: -v d="$dev" '$2==d {print $1}')
    fi
    info "Config deleted. Restart the network service to apply (or activate NIC in menu [3])."
}

show_iface_conf(){
    local dev
    echo
    echo "================ Current network configs ================"
    for dev in $(list_iface_configs); do
        echo "-- $dev --"
        [ -f "/etc/sysconfig/network-scripts/ifcfg-$dev" ] && { echo "  ifcfg: $(grep -E 'IPADDR|NETMASK|GATEWAY|DNS1' /etc/sysconfig/network-scripts/ifcfg-$dev | tr '\n' ' ')"; }
        [ -f "/etc/network/interfaces.d/$dev" ] && { echo "  interfaces.d: $(grep -E 'address|netmask|gateway' /etc/network/interfaces.d/$dev | tr '\n' ' ')"; }
        for f in /etc/netplan/*.yaml; do
            grep -q "^  $dev:" "$f" 2>/dev/null && { echo "  netplan: $f ($(grep -E '^\s+- ' "$f" | tr '\n' ' '))"; }
        done
        command -v nmcli >/dev/null 2>&1 && \
            nmcli -t -f NAME,DEVICE,STATE con show 2>/dev/null | grep -F ":$dev:" | sed 's/^/  nmcli: /'
    done
    echo "========================================================="
}

# ============================================================================
#  Connectivity test
# ============================================================================
test_connectivity(){
    local gw
    command -v ping >/dev/null || die "ping command not found, cannot test."
    echo
    echo "============================================================"
    echo "  Network Connectivity Test"
    echo "============================================================"
    gw=$(ip route show | awk '/^default/{print $3; exit}')
    info "Current $IFACE addr: $(ip -4 -o addr show dev "$IFACE" | awk '{print $4}')"
    echo "  [1/3] ping gateway ${gw:-<no default gateway>} ..."
    [ -n "$gw" ] && { ping -c 3 -W 2 "$gw" >/dev/null 2>&1 && info "  [OK] gateway reachable" || warn "  [X] gateway ping failed"; }
    echo "  [2/3] ping public 223.5.5.5 ..."
    ping -c 3 -W 2 223.5.5.5 >/dev/null 2>&1 && info "  [OK] public reachable" || warn "  [X] public ping failed (may be ICMP blocked)"
    echo "  [3/3] DNS resolve test (www.baidu.com) ..."
    getent hosts www.baidu.com >/dev/null 2>&1 && info "  [OK] DNS resolve OK" || warn "  [X] DNS resolve failed"
    echo "------------------------------------------------------------"
}

# ============================================================================
#  Main menu
# ============================================================================
main_menu(){
    while :; do
        echo
        echo "${BD}============================================${N}"
        echo "${BD}   Server Network Management Script v3.2-en${N}"
        echo "${BD}============================================${N}"
        echo "  [1] Configure Network IP (static, exclusive service)"
        echo "  [2] Backup / Restore network config"
        echo "  [3] Interface manage (up/down/activate/diagnose)"
        echo "  [4] Add / Delete NIC config"
        echo "  [0] Exit"
        echo "--------------------------------------------"
        local opt
        read -r -p "Select [0-4]: " opt
        case $opt in
            1) menu_configure ;;
            2) menu_backup ;;
            3) menu_iface_manage ;;
            4) menu_iface_conf ;;
            0) echo "Bye."; exit 0 ;;
            *) warn "Invalid input, try again." ;;
        esac
    done
}

main(){
    [ "$EUID" -eq 0 ] || die "Please run as root: sudo bash $0"
    detect_system
    main_menu
}

main "$@"
