#!/bin/bash
# multiwan_select.sh - 多WAN策略路由交互式助手 (防折行版)

# ---------- 自检 ----------
[ -n "${BASH_VERSION:-}" ] || { echo "请用 bash 运行"; exit 1; }
[ "$(id -u)" = "0" ] || { echo "请用 root 运行"; exit 1; }
if grep -q $'\r' "$0" 2>/dev/null; then
    sed -i 's/\r$//' "$0"
    echo "已把 CRLF 转成 LF，请重新运行: bash $0"
    exit 0
fi

# ---------- 1) 扫描网卡 ----------
mapfile -t NIC < <(ip -o -4 addr show scope global 2>/dev/null \
    | awk '{print $2}' | grep -v '^lo$' | sort -u)
if [ "${#NIC[@]}" -eq 0 ]; then
    echo "没有发现带 IPv4 的网卡，请先配置网络。"
    exit 1
fi

# 取 IP
get_ip() {
    ip -o -4 addr show dev "$1" 2>/dev/null \
        | awk 'NR==1{print $4}' | cut -d/ -f1
}
# 取网关(先取系统路由表，取不到再读 ifcfg 兜底)
get_gw() {
    local g
    g=$(ip -o route show default dev "$1" 2>/dev/null \
        | awk '/default via/{print $3; exit}')
    if [ -z "$g" ] && [ -f "/etc/sysconfig/network-scripts/ifcfg-$1" ]; then
        g=$(sed -n 's/^GATEWAY=//p' "/etc/sysconfig/network-scripts/ifcfg-$1" \
            | head -n1 | tr -d '\r" ')
    fi
    echo "$g"
}

NIC_IP=()
NIC_GW=()
for n in "${NIC[@]}"; do
    NIC_IP+=("$(get_ip "$n")")
    NIC_GW+=("$(get_gw "$n")")
done

# ---------- 2) 显示菜单 ----------
echo
echo "  序号  网卡    IP地址            网关            说明"
for i in "${!NIC[@]}"; do
    g="${NIC_GW[$i]}"
    if [ -n "$g" ]; then
        note="可作WAN出口"
    else
        note="无网关(内网口?)"
    fi
    printf "   %-4d %-6s %-17s %-14s %s\n" \
        $((i+1)) "${NIC[$i]}" "${NIC_IP[$i]}" "${g:----}" "$note"
done

echo
echo -n "选择要加入策略路由的网卡(逗号/空格分隔，回车=全部，支持 1-3): "
read -r SEL

# ---------- 3) 解析选择 ----------
PICK=()
if [ -z "$SEL" ]; then
    PICK=("${!NIC[@]}")
else
    read -ra parts <<< "$SEL"
    for p in "${parts[@]}"; do
        for x in ${p//,/ }; do
            if [[ "$x" =~ ^[0-9]+$ ]]; then
                if [ "$x" -ge 1 ] 2>/dev/null && [ "$x" -le "${#NIC[@]}" ] 2>/dev/null; then
                    PICK+=("$((x-1))")
                fi
            elif [[ "$x" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                a="${BASH_REMATCH[1]}"
                b="${BASH_REMATCH[2]}"
                if [ "$a" -ge 1 ] 2>/dev/null && [ "$b" -le "${#NIC[@]}" ] 2>/dev/null \
                    && [ "$a" -le "$b" ]; then
                    for ((y=a; y<=b; y++)); do
                        PICK+=("$((y-1))")
                    done
                fi
            else
                echo "  !! 无法识别 '$x'，已忽略"
            fi
        done
    done
fi
PICK=($(printf '%s\n' "${PICK[@]}" | sort -un))
if [ "${#PICK[@]}" -eq 0 ]; then
    echo "错误: 没有选中任何网卡。"
    exit 1
fi

# ---------- 4) 校验并固化(缺IP或缺网关自动剔除) ----------
WAN=()
WAN_IP=()
WAN_GW=()
echo "  已选(顺序即优先级，无效项自动剔除):"
for i in "${PICK[@]}"; do
    ip="${NIC_IP[$i]}"
    gw="${NIC_GW[$i]}"
    if [ -z "$ip" ] || [ -z "$gw" ]; then
        echo "    !! 跳过 ${NIC[$i]}: 缺IP或缺网关"
        continue
    fi
    WAN+=("${NIC[$i]}")
    WAN_IP+=("$ip")
    WAN_GW+=("$gw")
    echo "    ✓ ${NIC[$i]}  ip=$ip  gw=$gw"
done
if [ "${#WAN[@]}" -eq 0 ]; then
    echo "错误: 所选网卡都没有完整的 IP+网关。"
    exit 1
fi

# ---------- 5) 表号与 rp_filter ----------
echo -n "路由表起始编号 [默认200, 每接口+1]: "
read -r BASE
if [[ "$BASE" =~ ^[0-9]+$ ]] && [ "$BASE" -ge 2 ] && [ "$BASE" -le 251 ]; then
    :
else
    BASE=200
fi
WAN_TBL=()
n=$BASE
for w in "${WAN[@]}"; do
    WAN_TBL+=("$n")
    n=$((n+1))
done

echo -n "rp_filter 模式 [0=关闭, 2=宽松, 默认0]: "
read -r RP
[ "$RP" = "2" ] || RP=0

# ---------- 6) 预览确认 ----------
echo
echo "  将写入以下策略路由:"
for i in "${!WAN[@]}"; do
    echo "    table ${WAN_TBL[$i]} ${WAN[$i]}  via ${WAN_GW[$i]} src ${WAN_IP[$i]}"
done
echo -n "  确认写入并应用? [y/N]: "
read -r OK
if [ "$OK" != "y" ] && [ "$OK" != "Y" ]; then
    echo "已取消，未做任何修改。"
    exit 0
fi

# ---------- 7) 备份 ----------
BK="/root/multiwan_bak_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BK"
cp -a /etc/rc.local "$BK/" 2>/dev/null
cp -a /etc/sysctl.conf "$BK/" 2>/dev/null
cp -a /etc/iproute2/rt_tables "$BK/" 2>/dev/null
echo "  备份 -> $BK"

# ---------- 8) 清理旧规则 ----------
sed -i -r '/^ip (route|rule).*/d' /etc/rc.local
sed -i '/\/proc\/sys\/net\/ipv4\/conf/d' /etc/rc.local
ip rule show 2>/dev/null \
    | awk '/lookup/ && $NF!~/^(local|main|default|unspec)$/ {print $NF}' \
    | sort -u | while read -r t; do
        ip route flush table "$t" 2>/dev/null
        while ip rule del table "$t" 2>/dev/null; do :; done
    done

# ---------- 9) rp_filter + sysctl ----------
echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
echo 0 > /proc/sys/net/ipv4/conf/default/rp_filter
{
    echo "# rebuilt by multiwan_select"
    echo "net.ipv4.conf.all.rp_filter=$RP"
    echo "net.ipv4.conf.default.rp_filter=$RP"
    for w in "${WAN[@]}"; do
        echo "net.ipv4.conf.$w.rp_filter=$RP"
    done
} > /etc/sysctl.conf
sysctl -p /etc/sysctl.conf >/dev/null 2>&1

# ---------- 10) rt_tables ----------
{
    echo "# reserved values"
    echo "255	local"
    echo "254	main"
    echo "253	default"
    echo "0	unspec"
} > /etc/iproute2/rt_tables
for i in "${!WAN[@]}"; do
    echo "${WAN_TBL[$i]} ${WAN[$i]}" >> /etc/iproute2/rt_tables
done

# ---------- 11) rc.local ----------
for i in "${!WAN[@]}"; do
    cat >> /etc/rc.local <<EOF
ip route flush table ${WAN[$i]}
ip route add default via ${WAN_GW[$i]} dev ${WAN[$i]} src ${WAN_IP[$i]} table ${WAN[$i]}
ip rule add from ${WAN_IP[$i]} table ${WAN[$i]}
EOF
done

chmod +x /etc/rc.local
systemctl enable rc-local >/dev/null 2>&1
. /etc/rc.local 2>/dev/null

echo
echo "======== 配置完成 ========"
ip rule show
