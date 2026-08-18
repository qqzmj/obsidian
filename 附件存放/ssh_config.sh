#!/usr/bin/env bash
# =====================================================
# 文件名: config_ssh_interactive.sh
# 用途  : 交互式配置 SSH（你自己选择每一项，默认值带 default 标识）
#         支持: Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux / Fedora
# 用法  : sudo bash config_ssh_interactive.sh
# =====================================================
set -euo pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"
CONF_BACKUP="${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
q()     { echo -en "${CYAN}?${NC} $*"; }

[[ $EUID -eq 0 ]] || { error "请用 root 运行: sudo bash $0"; exit 1; }

# ============================================================
# ① 系统检测（只用于安装包/防火墙/服务名等基础操作）
# ============================================================
detect_env() {
    . /etc/os-release
    case "$ID" in
        ubuntu|debian)
            FAMILY="debian"; DISTRO="$NAME $VERSION_ID"
            PM="apt"; SVC_NAME="ssh"
            ;;
        centos|rhel|rocky|almalinux|fedora|ol|amzn)
            FAMILY="redhat"; DISTRO="$NAME $VERSION_ID"
            command -v dnf >/dev/null 2>&1 && PM="dnf" || PM="yum"
            SVC_NAME="sshd"
            ;;
        *) error "不支持的发行版: $NAME"; exit 1 ;;
    esac
    command -v sshd >/dev/null 2>&1 && SSH_VER=$(sshd -V 2>&1 | grep -oP 'OpenSSH_\K[0-9.]+' | head -1) || SSH_VER="未安装"
    [[ -d /run/systemd/system ]] && INIT="systemd" || INIT="sysvinit"
    command -v getenforce >/dev/null 2>&1 && SELINUX_MODE=$(getenforce) || SELINUX_MODE="无"
}

# ============================================================
# ② 交互菜单（默认值统一带 [default] 标识）
# ============================================================
interactive_config() {
    echo; echo "=============== 开始配置 SSH ==============="
    echo "系统: $DISTRO / OpenSSH ${SSH_VER} / 服务名: $SVC_NAME"
    echo "提示: 直接回车=使用标注 [default] 的选项"
    echo "==============================================="

    # --- 端口 (默认 22) ---
    q "SSH 监听端口 [22] [default]: "
    read -r SSH_PORT; SSH_PORT="${SSH_PORT:-22}"

    # --- root 登录 (默认 3=禁止root) ---
    echo; echo "root 登录方式:"
    echo "  1) yes                允许 root 用密码登录"
    echo "  2) prohibit-password  仅允许 root 密钥登录"
    echo "  3) no                 完全禁止 root 登录(推荐,用普通用户+sudo)  [default]"
    q "请选择 [3]: "
    read -r ROOT_CHOICE
    case "${ROOT_CHOICE:-3}" in
        1) ALLOW_ROOT_LOGIN="yes" ;;
        2) ALLOW_ROOT_LOGIN="prohibit-password" ;;
        3) ALLOW_ROOT_LOGIN="no" ;;
        *) ALLOW_ROOT_LOGIN="no" ;;
    esac

    # --- 密码认证 (默认 y=允许) ---
    echo; q "允许密码认证? (y/n) [y] [default]: "
    read -r PASSWORD_AUTH
    if [[ "${PASSWORD_AUTH:-y}" == "y" ]]; then
        PASSWORD_AUTH="yes"
    else
        PASSWORD_AUTH="no"
        warn "关闭密码认证前，请确认已配置密钥，否则无法登录！"
    fi

    # --- 公钥认证 (默认 y=允许) ---
    q "允许公钥认证? (y/n) [y] [default]: "
    read -r PUBKEY_AUTH
    [[ "${PUBKEY_AUTH:-y}" == "y" ]] && PUBKEY_AUTH="yes" || PUBKEY_AUTH="no"

    # --- 禁止空密码 (默认 y=禁止) ---
    q "禁止空密码账户登录? (y/n) [y] [default]: "
    read -r EMPTY_PASS
    [[ "${EMPTY_PASS:-y}" == "y" ]] && EMPTY_PASS="no" || EMPTY_PASS="yes"

    # --- 用户白名单 (默认 空=不限制) ---
    echo; echo "用户白名单(可选): 只允许指定用户登录，多个用空格分隔"
    echo "示例: alice bob"
    q "允许的用户 [留空=不限制] [default]: "
    read -r ALLOW_USERS

    # --- 防爆破参数 (默认 3 / 60) ---
    q "最大认证尝试次数(防爆破) [3] [default]: "
    read -r MAX_TRIES; MAX_TRIES="${MAX_TRIES:-3}"
    q "登录超时秒数 [60] [default]: "
    read -r GRACE_TIME; GRACE_TIME="${GRACE_TIME:-60}"
    q "开启客户端存活检测? (y/n) [y] [default]: "
    read -r ALIVE_CHECK
    if [[ "${ALIVE_CHECK:-y}" == "y" ]]; then
        ALIVE_INTERVAL="300"; ALIVE_COUNT="2"
        info "存活检测: 每300秒探测，连续2次无响应断开"
    else
        ALIVE_INTERVAL="0"; ALIVE_COUNT="0"
    fi

    # --- X11 转发 (默认 n=禁止) ---
    q "允许 X11 图形转发? (y/n) [n] [default]: "
    read -r X11_FWD
    [[ "${X11_FWD:-n}" == "y" ]] && X11_FWD="yes" || X11_FWD="no"

    # --- TCP 转发 (默认 n=禁止) ---
    q "允许 TCP 端口转发(SSH隧道/代理)? (y/n) [n] [default]: "
    read -r TCP_FWD
    [[ "${TCP_FWD:-n}" == "y" ]] && TCP_FWD="yes" || TCP_FWD="no"

    # --- UseDNS (默认 y=关闭) ---
    q "关闭 UseDNS 反向解析(加速连接)? (y/n) [y] [default]: "
    read -r USE_DNS
    [[ "${USE_DNS:-y}" == "y" ]] && USE_DNS="no" || USE_DNS="yes"

    # --- 防火墙 (默认 1=自动放行) ---
    echo; echo "防火墙处理:"
    echo "  1) 用系统防火墙放行端口 (ufw/firewalld)  [default]"
    echo "  2) 跳过防火墙配置(我自己处理)"
    q "请选择 [1]: "
    read -r FW_CHOICE
    [[ "${FW_CHOICE:-1}" == "2" ]] && DO_FIREWALL="no" || DO_FIREWALL="yes"

    # --- 登录横幅 (默认 n=不设置) ---
    q "设置登录警告横幅? (y/n) [n] [default]: "
    read -r SET_BANNER
    if [[ "${SET_BANNER:-n}" == "y" ]]; then
        BANNER_FILE="/etc/ssh/banner"
        q "横幅文字 [警告: 仅限授权用户访问，一切操作将被记录]: "
        read -r BANNER_TEXT
        echo "${BANNER_TEXT:-警告: 仅限授权用户访问，一切操作将被记录}" > "$BANNER_FILE"
        info "横幅已写入 $BANNER_FILE"
    else
        BANNER_FILE=""
    fi

    # --- 汇总确认 (默认 y=确认) ---
    echo; echo "=============== 配置汇总 ==============="
    echo "  端口           : $SSH_PORT"
    echo "  root 登录      : $ALLOW_ROOT_LOGIN"
    echo "  密码认证       : $PASSWORD_AUTH"
    echo "  公钥认证       : $PUBKEY_AUTH"
    echo "  禁止空密码     : $EMPTY_PASS"
    echo "  允许用户       : ${ALLOW_USERS:-不限制}"
    echo "  认证尝试上限   : $MAX_TRIES 次"
    echo "  登录超时       : $GRACE_TIME 秒"
    echo "  存活检测       : ${ALIVE_INTERVAL}秒/${ALIVE_COUNT}次"
    echo "  X11 转发       : $X11_FWD"
    echo "  TCP 转发       : $TCP_FWD"
    echo "  UseDNS         : $USE_DNS"
    echo "  防火墙处理     : $DO_FIREWALL"
    echo "  登录横幅       : ${BANNER_FILE:-无}"
    echo "==========================================="
    q "确认写入配置? (y/n) [y] [default]: "
    read -r CONFIRM
    [[ "${CONFIRM:-y}" == "y" ]] || { info "已取消，未做任何修改。"; exit 0; }
}

# ============================================================
# ③ 安装 openssh-server
# ============================================================
install_openssh() {
    command -v sshd >/dev/null 2>&1 && { info "sshd 已安装，跳过。"; return; }
    export DEBIAN_FRONTEND=noninteractive
    info "使用 $PM 安装 openssh-server ..."
    case "$PM" in
        apt) apt update -y && apt install -y openssh-server ;;
        dnf) dnf install -y openssh-server ;;
        yum) yum install -y openssh-server ;;
    esac
    SSH_VER=$(sshd -V 2>&1 | grep -oP 'OpenSSH_\K[0-9.]+' | head -1)
}

# ============================================================
# ④ 生成配置
# ============================================================
build_config() {
    cp -a "$SSHD_CONFIG" "$CONF_BACKUP" 2>/dev/null || true
    info "原配置已备份: $CONF_BACKUP"

    if [[ -d "$DROPIN_DIR" ]] && grep -q "Include $DROPIN_DIR" "$SSHD_CONFIG" 2>/dev/null; then
        CONFIG_TARGET="$DROPIN_DIR/99-ssh-config.conf"
    else
        CONFIG_TARGET="$SSHD_CONFIG"
    fi
    mkdir -p "$(dirname "$CONFIG_TARGET")"

    cat > "$CONFIG_TARGET" <<EOF
# ===== 由 config_ssh_interactive.sh 于 $(date '+%F %T') 生成 =====
# 系统: $DISTRO / OpenSSH $SSH_VER

Port $SSH_PORT
PermitRootLogin $ALLOW_ROOT_LOGIN
PubkeyAuthentication $PUBKEY_AUTH
PasswordAuthentication $PASSWORD_AUTH
PermitEmptyPasswords $EMPTY_PASS
UsePAM yes
MaxAuthTries $MAX_TRIES
LoginGraceTime $GRACE_TIME
ClientAliveInterval $ALIVE_INTERVAL
ClientAliveCountMax $ALIVE_COUNT
X11Forwarding $X11_FWD
AllowTcpForwarding $TCP_FWD
UseDNS $USE_DNS
StrictModes yes
LogLevel VERBOSE
EOF

    if [[ "$(echo -e "$SSH_VER\n7.3" | sort -V | tail -1)" == "$SSH_VER" ]]; then
        echo "KbdInteractiveAuthentication no" >> "$CONFIG_TARGET"
    else
        echo "ChallengeResponseAuthentication no" >> "$CONFIG_TARGET"
    fi

    [[ -n "$ALLOW_USERS" ]] && echo "AllowUsers $ALLOW_USERS" >> "$CONFIG_TARGET"
    [[ -n "$BANNER_FILE" ]] && echo "Banner $BANNER_FILE" >> "$CONFIG_TARGET"
    [[ "$PASSWORD_AUTH" == "no" ]] && echo "AuthenticationMethods publickey" >> "$CONFIG_TARGET"

    info "校验 sshd 配置语法 ..."
    if ! sshd -t; then
        error "语法校验失败！回滚: cp $CONF_BACKUP $SSHD_CONFIG && systemctl restart $SVC_NAME"
        exit 1
    fi
}

# ============================================================
# ⑤ SELinux（CentOS 改端口必需）
# ============================================================
configure_selinux() {
    [[ "$FAMILY" != "redhat" ]] && return 0
    if [[ "$SELINUX_MODE" == "Enforcing" || "$SELINUX_MODE" == "Permissive" ]]; then
        if [[ "$SSH_PORT" != "22" ]]; then
            info "SELinux 开启且端口改为 $SSH_PORT，放行端口 ..."
            if ! command -v semanage >/dev/null 2>&1; then
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y policycoreutils-python-utils >/dev/null 2>&1
                else
                    yum install -y policycoreutils-python >/dev/null 2>&1
                fi
            fi
            if command -v semanage >/dev/null 2>&1; then
                semanage port -a -t ssh_port_t -p tcp "$SSH_PORT" 2>/dev/null \
                    || semanage port -m -t ssh_port_t -p tcp "$SSH_PORT"
                info "SELinux 已放行端口 $SSH_PORT/tcp"
            else
                warn "semanage 安装失败，请手动执行放行命令！"
            fi
        fi
        if [[ "$ALLOW_ROOT_LOGIN" != "no" ]]; then
            warn "若 root 密钥登录被 SELinux 拦截，执行: setsebool -P ssh_sysadm_login 1"
        fi
    fi
}

# ============================================================
# ⑥ 防火墙
# ============================================================
configure_firewall() {
    [[ "$DO_FIREWALL" == "no" ]] && { info "按你的选择跳过防火墙配置。"; return; }
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "$SSH_PORT/tcp" >/dev/null 2>&1 && info "ufw 已放行 $SSH_PORT/tcp" || warn "ufw 放行失败"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="$SSH_PORT/tcp" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        info "firewalld 已放行 $SSH_PORT/tcp"
    else
        warn "未检测到 ufw/firewalld，请自行放行 $SSH_PORT/tcp"
    fi
}

# ============================================================
# ⑦ 服务管理
# ============================================================
start_service() {
    if [[ "$INIT" == "systemd" ]]; then
        systemctl enable "$SVC_NAME" >/dev/null 2>&1
        systemctl restart "$SVC_NAME"
        info "服务 $SVC_NAME 已启动并开机自启"
    else
        service "$SVC_NAME" restart 2>/dev/null
        update-rc.d "$SVC_NAME" enable 2>/dev/null || chkconfig "$SVC_NAME" on 2>/dev/null
        warn "使用 sysvinit 启动"
    fi
}

# ============================================================
# ⑧ 完成
# ============================================================
print_summary() {
    local ip; ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo; echo "=============================================="
    info "SSH 配置完成！"
    echo "  系统          : $DISTRO"
    echo "  端口          : $SSH_PORT"
    echo "  root 登录     : $ALLOW_ROOT_LOGIN"
    echo "  密码认证      : $PASSWORD_AUTH"
    echo "  配置写入位置  : $CONFIG_TARGET"
    echo "  备份文件      : $CONF_BACKUP"
    echo "----------------------------------------------"
    echo "  本机连接      : ssh -p $SSH_PORT $USER@127.0.0.1"
    echo "  局域网连接    : ssh -p $SSH_PORT $USER@$ip"
    echo "=============================================="
}

# ---------- 主流程 ----------
main() {
    detect_env
    interactive_config
    install_openssh
    build_config
    configure_selinux
    configure_firewall
    start_service
    print_summary
}
main "$@"
