# Linux 防火墙运维实战手册：iptables 与 firewalld 原理、配置与场景实践

## 1. 防火墙基础认知：Netfilter 框架

无论 iptables 还是 firewalld，其底层内核实现都是 **Netfilter**——Linux 内核中定义在内核网络协议栈各关键路径上的钩子（hooks）框架。

理解 Netfilter 是理解一切的前提：

- 数据包在协议栈中会经过 **5 个固定的钩子点（hook points）**；
- 用户态工具（iptables/nftables）通过规则集，告诉内核"在哪个钩子点、匹配什么条件、做什么动作"；
- 规则按顺序匹配，命中即执行动作，未命中则落入下一条规则，直到默认策略。

### 5 个钩子点（与内核常量对应）

| 钩子点 | 内核常量 | 触发时机 |
|--------|----------|----------|
| PREROUTING | NF_INET_PRE_ROUTING | 数据包进入本机，路由决策**之前** |
| INPUT | NF_INET_LOCAL_IN | 数据包目的地为本机，交给本地进程**之前** |
| FORWARD | NF_INET_FORWARD | 数据包目的地非本机，需经本机转发（路由后） |
| OUTPUT | NF_INET_LOCAL_OUT | 本机进程产生的数据包发出时 |
| POSTROUTING | NF_INET_POST_ROUTING | 数据包离开本机，路由决策**之后**、发送之前 |

> **运维直觉**：PREROUTING 管"入口改包"（DNAT 在这里），POSTROUTING 管"出口改包"（SNAT/MASQUERADE 在这里），INPUT/FORWARD/OUTPUT 管"放行还是丢弃"。

---

## 2. iptables 原理深入

### 2.1 四表五链（多链表格映射）

iptables 的规则不是一条平铺的列表，而是按 **表（table）→ 链（chain）→ 规则（rule）** 三级组织。表按"职责"划分，链按"钩子点"划分，二者通过"哪些表挂在哪些链上"形成网格。

**标准五张表：**

| 表 | 职责 | 挂载的链 | 典型用途 |
|----|------|----------|----------|
| **raw** | 关闭连接跟踪 | PREROUTING, OUTPUT | 高流量场景对特定包跳过 conntrack（性能） |
| **mangle** | 修改包头/标记 | 全部 5 条链 | TOS、TTL、MARK（配合策略路由/QoS） |
| **nat** | 地址转换 | PREROUTING, INPUT, OUTPUT, POSTROUTING | DNAT / SNAT / MASQUERADE / REDIRECT |
| **filter** | 过滤（默认表） | INPUT, FORWARD, OUTPUT | 放行/拒绝（防火墙核心工作） |
| **security** | SELinux 强制访问控制标记 | INPUT, FORWARD, OUTPUT | 配合 SELinux（多数场景用不到） |

**表在同一链上的执行顺序（重要！）：**
```
PREROUTING:  raw → mangle → nat
INPUT:       mangle → filter → security
FORWARD:     mangle → filter → security
OUTPUT:      raw → mangle → nat → filter → security
POSTROUTING: mangle → nat
```

> 默认情况下 iptables 操作的是 **filter 表**，必须用 `-t 表名` 显式指定其他表。

### 2.2 数据包完整流转路径

```
┌──────────────────────────────────────────────────────────────┐
│ 数据包进入网卡                                                  │
│   ↓                                                           │
│ PREROUTING (raw→mangle→nat)                                   │
│   │── 路由决策 ──┐                                             │
│   │             │                                             │
│   │ 目的=本机     │ 目的≠本机（需转发）                            │
│   ↓             ↓                                             │
│  INPUT          FORWARD (mangle→filter→security)              │
│  (mangle→filter)│                                             │
│   ↓             ↓                                             │
│  本机进程       POSTROUTING (mangle→nat)                       │
│                ↓                                              │
│               出网卡                                           │
└──────────────────────────────────────────────────────────────┘
  本机进程发包：OUTPUT (raw→mangle→nat→filter→security)
               → POSTROUTING (mangle→nat) → 出网卡
```

**两个高频考点：**
1. **转发包（FORWARD）**：仅经过 PREROUTING → FORWARD → POSTROUTING，**不经过 INPUT 和 OUTPUT**。做路由网关/内网转发时，放行规则必须写 FORWARD 链，写 INPUT/OUTPUT 无效——这是新手最常见的错误。
2. **DNAT 之后路由重决策**：PREROUTING 的 DNAT 会改变目标地址，内核会**重新做一次路由决策**，这正是 DNAT 能把外部流量转发到内网主机的原因。

### 2.3 连接跟踪（conntrack）机制

iptables 的"状态防火墙"能力依赖内核的 `nf_conntrack` 模块。

**四个状态：**

| 状态 | 含义 |
|------|------|
| NEW | 新建连接的第一个包 |
| ESTABLISHED | 已建立双向会话（能识别应答） |
| RELATED | 与已有连接相关联的新连接（典型：FTP 数据连接、ICMP 错误回报） |
| INVALID | 无法识别/非法包（应丢弃） |

**经典状态防火墙三段式规则（务必掌握）：**
```bash
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW -j ACCEPT
```

> - 现代内核推荐 `-m conntrack --ctstate`；`-m state --state` 是旧写法，二者等价但前者是当前的规范写法。
> - **场景影响**：NAT 必须依赖 conntrack；`nf_conntrack_max` 满会导致"能 ping 通但建不了新连接"，这是高并发 NAT 网关的经典故障。
> - 性能调优：raw 表的 `NOTRACK`（iptables）可以跳过跟踪，但会**丧失状态能力**，属于"以功能换性能"，慎用。

### 2.4 匹配（match）与目标（target）

**匹配条件**决定"这条规则管什么样的包"，**目标**决定"命中后做什么"。

常用匹配：

| 匹配 | 示例 | 说明 |
|------|------|------|
| 源/目的地址 | `-s 10.0.0.0/8` `-d 8.8.8.8` | 支持 CIDR、`!` 取反 |
| 接口 | `-i eth0` `-o eth1` | 入/出接口 |
| 协议 | `-p tcp/udp/icmp` | |
| 端口（tcp/udp） | `--dport 22` `--sport 1024:65535` | 需配合 `-p` |
| 多端口 | `-m multiport --dports 80,443,8080` | |
| 连接状态 | `-m conntrack --ctstate NEW` | |
| TCP 标志 | `-m tcp --syn` `--tcp-flags ALL FIN,SYN,RST,PSH,ACK,URG` | 防扫描/畸形包 |
| 速率限制 | `-m limit --limit 10/s --limit-burst 20` | 限速（防洪水） |
| 时间 | `-m time --timestart 09:00 --timestop 18:00` | 时段控制 |
| 源 MAC | `-m mac --mac-source 00:11:22:33:44:55` | 局域网绑定 |
| ipset | `-m set --match-set 黑名单源 src` | 大数据量匹配 |
| 字符串 | `-m string --algo bm --string "GET /shell"` | 应用层内容过滤（有性能代价） |
| 地址类型 | `-m addrtype --dst-type LOCAL` | 判断包目的地类型 |

常用目标：

| 目标 | 行为 | 说明 |
|------|------|------|
| ACCEPT | 放行 | 不再匹配后续规则 |
| DROP | 丢弃 | 不回应（对攻击者"隐身"） |
| REJECT | 拒绝 | 回应 `--reject-with icmp-port-unreachable` 等，明确告知 |
| LOG | 记录日志 | 命中后**继续**匹配下一条，常与 DROP 组合 |
| SNAT | 源地址转换 | 在 POSTROUTING：`-j SNAT --to-source 1.2.3.4` |
| MASQUERADE | 动态源地址转换 | 出口 IP 动态（拨号）时用，性能略低于 SNAT |
| DNAT | 目的地址转换 | 在 PREROUTING：`-j DNAT --to-destination 10.0.0.5:80` |
| REDIRECT | 本机端口重定向 | `-j REDIRECT --to-ports 3128`（透明代理常用） |
| MARK | 打标记 | 配合 `ip rule` 策略路由 / tc QoS |
| RETURN | 返回调用链 | 自定义链提前结束 |
| SET | 动态写入 ipset | 自动封禁/动态名单 |

---

## 3. iptables 使用方法与命令速查

### 3.1 命令语法总纲

```
iptables [-t 表名] 动作 链 [规则编号] [匹配条件] -j 目标
```

**常用动作（管理操作）：**

| 动作                                      | 含义                |
| --------------------------------------- | ----------------- |
| `-A chain`                              | 追加规则到链尾           |
| `-I chain [num]`                        | 插入规则到链首（或指定编号处）   |
| `-D chain [num]` 或 `-D chain 规则`        | 删除规则              |
| `-F [chain]`                            | 清空（flush）链/表内所有规则 |
| `-X [chain]`                            | 删除自定义空链           |
| `-P chain target`                       | 设置默认策略            |
| `-L [chain] [-n] [-v] [--line-numbers]` | 列出规则（数字/详细/带行号）   |
| `-Z [chain]`                            | 计数器清零             |
| `-N chain`                              | 新建自定义链            |
| `-E old new`                            | 重命名链              |

### 3.2 查看类命令（排错第一武器）

```bash
# 基础查看（filter 表）
iptables -L -n -v --line-numbers

# 查看 NAT 表（端口转发排错必查）
iptables -t nat -L -n -v --line-numbers

# 查看 mangle / raw 表
iptables -t mangle -L -n -v

# 完整导出当前所有规则（最可靠的"现状快照"）
iptables-save

# 查看规则计数器实时变化（确认流量是否命中某条规则）
watch -n 1 'iptables -L -n -v'
```

> 查看时 `-v` 的前两列 `pkts`/`bytes` 是计数器——排错时"规则没生效"往往是因为**计数器为 0，包根本没走到这条链**。

### 3.3 新增规则示例

```bash
# 1. 允许本机回环
iptables -A INPUT -i lo -j ACCEPT

# 2. 放行已建立连接
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 3. 仅允许 10.1.1.0/24 访问 SSH
iptables -A INPUT -p tcp --dport 22 -s 10.1.1.0/24 -m conntrack --ctstate NEW -j ACCEPT

# 4. 放行 80/443
iptables -A INPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW -j ACCEPT

# 5. 拒绝所有其他入站（默认策略兜底）
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 6. 记录并丢弃来自某 IP 的包
iptables -A INPUT -s 1.2.3.4 -j LOG --log-prefix "BLOCKED: " --log-level 4
iptables -A INPUT -s 1.2.3.4 -j DROP
```

### 3.4 修改/删除/清空

```bash
# 按行号插入到第 2 条
iptables -I INPUT 2 -p icmp -j ACCEPT

# 按行号删除
iptables -D INPUT 5

# 按完整规则删除
iptables -D INPUT -p tcp --dport 22 -j ACCEPT

# 清空 filter 表 INPUT 链
iptables -F INPUT

# 重置默认策略（防止误清空后网络断开的兜底手段）
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
```

> **高危警示**：`iptables -F` 会清空规则，若默认策略是 DROP，清空瞬间会**全部拒绝**，远程连接直接中断。生产操作前务必先确认默认策略，或先 `-P ACCEPT` 再 `-F`。

### 3.5 NAT 与端口转发

```bash
# 源 NAT：内网 192.168.100.0/24 出外网时伪装成 eth0 出口 IP
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o eth0 -j MASQUERADE

# 源 NAT：固定出口 IP（性能更优）
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o eth0 -j SNAT --to-source 203.0.113.10

# 目的 NAT：公网 80 → 内网 10.0.0.5:80
iptables -t nat -A PREROUTING -d 203.0.113.10 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.5:80

# 同机端口重定向：8080 → 80（透明重定向/代理场景）
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j REDIRECT --to-ports 80

# 启用内核转发（NAT 网关必需）
echo 1 > /proc/sys/net/ipv4/ip_forward   # 临时
# 永久：写入 /etc/sysctl.conf 的 net.ipv4.ip_forward=1，sysctl -p
```

> NAT 网关**必须同时放行 FORWARD 链**，例如：
> `iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT`
> `iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT`

### 3.6 ipset：大数据量黑名单

当封禁名单上千条时，逐条写规则会导致内核线性遍历，性能急剧下降。此时用 ipset：

```bash
# 创建 hash:ip 集合
ipset create blacklist hash:ip timeout 0

# 批量添加
ipset add blacklist 1.2.3.4
ipset add blacklist 5.6.7.8

# 绑定一条 iptables 规则即可匹配整个集合
iptables -I INPUT -m set --match-set blacklist src -j DROP

# 带超时自动解封（DDoS 动态封禁）：
# ipset create tempban hash:ip timeout 3600
# ipset add tempban 1.2.3.4 timeout 3600
# iptables -I INPUT -m set --match-set tempban src -j DROP
```

### 3.7 简易抗 DDoS / 洪水防护

```bash
# 1. 开启内核 SYN Cookies（防 SYN Flood 的基础手段）
#    net.ipv4.tcp_syncookies = 1

# 2. ICMP 限速（防 ping 洪水）
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 5/s --limit-burst 10 -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP

# 3. 新连接速率限制（防连接洪水）
iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m limit --limit 20/s --limit-burst 50 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -j DROP

# 4. 丢弃畸形/异常 TCP 标志包
iptables -A INPUT -p tcp --tcp-flags ALL FIN,SYN,RST,PSH,ACK,URG -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP

# 5. 丢弃明显伪造源地址的包
iptables -A INPUT -s 127.0.0.0/8 ! -i lo -j DROP
iptables -A INPUT -s 10.0.0.0/8 ! -i eth1 -j DROP
```

---

## 4. iptables 规则持久化

iptables 规则**默认只存在于内存**，重启即失。持久化三件套：

### 4.1 导出/导入

```bash
# 导出当前全部规则（含 nat/mangle/raw）
iptables-save > /etc/sysconfig/iptables        # RHEL/CentOS 习惯路径
iptables-save > /root/backup-iptables-$(date +%F).rules

# 恢复
iptables-restore < /etc/sysconfig/iptables

# 按表导出
iptables-save -t nat
```

### 4.2 开机自动加载

**RHEL/CentOS 系（iptables-services）：**
```bash
yum install -y iptables-services
systemctl enable --now iptables
# 之后规则自动保存/恢复由服务管理，重启不丢
```

**Debian/Ubuntu 系（iptables-persistent）：**
```bash
apt install -y iptables-persistent
netfilter-persistent save      # 保存当前规则
netfilter-persistent reload    # 重新加载
# 规则存于 /etc/iptables/rules.v4 和 rules.v6
```

### 4.3 运维纪律

- 每次变更前先 `iptables-save` 备份；
- 变更后**立即验证**（新开一个终端测试连通性再关闭旧会话）；
- 建议把"清空并放行"脚本作为救援手段预先写好。

---

## 5. firewalld 原理深入

### 5.1 定位与架构

firewalld 是 RHEL/CentOS 7+ 的默认防火墙守护进程，**它本身不实现包过滤，而是规则的管理框架**：

```
firewall-cmd (CLI)  ──►  firewalld (daemon)  ──►  后端规则集
                                                       │
                                   ┌───────────────────┴─────────────────┐
                       传统后端：iptables             现代后端：nftables
                   (RHEL7/8 早期默认)                (RHEL8.2+/RHEL9 默认)
```

**与 iptables 的本质区别（运维视角最重要的一条）：**

| 维度     | iptables                 | firewalld                             |
| ------ | ------------------------ | ------------------------------------- |
| 变更生效方式 | 手工逐条改，规则**即刻生效**但需自行管理顺序 | 变更需 `--reload` 应用，由守护进程统一管理顺序         |
| 配置模型   | 链/规则（底层视角）               | Zone/Service（业务视角）                    |
| 动态性    | 手动维护                     | 支持动态加载服务、规则去重                         |
| 一致性    | 内存规则与配置文件需手动同步           | **runtime（运行）与 permanent（永久）双配置自动管理** |
| 默认策略   | 需自行设定                    | 各 zone 预置明确策略                         |

### 5.2 Zone（区域）模型——firewalld 的核心设计

Zone 是对"信任级别"的抽象。**每个网络接口（或源地址）在同一时刻只属于一个 zone**，规则按 zone 组织。

**预置 zone（信任度从低到高）：**

| Zone | 信任级别 | 默认放行 |
|------|----------|----------|
| drop | 最低 | 全部丢弃（仅保留已建立连接） |
| block | 低 | 拒绝入站（回显 icmp-host-prohibited） |
| public | 低（默认） | 仅 ssh、dhcpv6-client |
| external | 低（NAT 出口场景） | 默认启用 masquerade，仅 ssh |
| dmz | 中（隔离区） | 仅 ssh |
| work / home / internal | 中 | ssh、ipp-client、dhcpv6-client、mdns、samba-client |
| trusted | 最高 | 全部放行（内网/管理网常用） |

**Zone 的匹配顺序**：firewalld 按"最具体优先"匹配——先按**接口**归属，再按**源地址**归属（`--add-source`），都没有则落到默认 zone。

**运维心法**：不要把所有东西堆在 public 上，而是"**把接口/网段划到合适 zone，再对 zone 开服务**"。

### 5.3 Runtime 与 Permanent 双配置模型

这是 firewalld 区别于 iptables 的最大改进，也是新手最容易踩的坑：

```bash
firewall-cmd --add-service=http            # 1. 立即生效（runtime）
firewall-cmd --permanent --add-service=http # 2. 写入配置文件（permanent，不立即生效）
firewall-cmd --reload                       # 3. 用 permanent 覆盖 runtime
```

- **不加 `--permanent`**：只改运行时（内存），`--reload` 或重启后丢失；
- **加 `--permanent`**：只写 `/etc/firewalld/` 下的持久化文件，**不立即生效**，需 `--reload`；
- `--reload`：用 permanent 配置重建运行时（**保留状态，不中断已建连接**）；
- `--complete-reload`：完全重建（中断所有连接，慎用）。

**最佳操作习惯**：
```bash
# 推荐：permanent + 立即生效一步到位
firewall-cmd --permanent --add-service=http
firewall-cmd --reload
# 或合并写法
firewall-cmd --add-service=http --permanent --reload
```

### 5.4 配置存储位置

```
/usr/lib/firewalld/    # 发行版自带的默认配置（勿改，更新会被覆盖）
/etc/firewalld/        # 管理员自定义配置（优先于默认）
  ├── firewalld.conf   # 主配置：默认 zone、后端、日志等
  ├── zones/*.xml      # zone 定义（rich rule、服务、端口等）
  ├── services/*.xml   # 自定义服务定义
  ├── icmptypes/  policies/  helpers/...
```

### 5.5 后端与 nftables 迁移

- RHEL 8.2+、RHEL 9、Rocky/Alma 9：firewalld 默认后端为 **nftables**；
- RHEL 7 / 8 早期：默认后端为 iptables；
- 后端可用 `firewall-cmd --get-backend` 查看；
- 现代系统上 `iptables` 命令往往只是 nftables 的兼容翻译层，直接用 `iptables-save` 看到的可能是翻译后的 nft 规则，**不要用它来修改 firewalld 管理的规则**（会被 firewalld 覆盖）。

> 建议：新系统统一通过 `firewall-cmd` 管理；确需底层规则用 `nft`（nftables 原生命令）或 firewalld 的 direct/rich rule。

---

## 6. firewalld 使用方法与命令速查

### 6.1 基础状态查询

```bash
systemctl status firewalld
firewall-cmd --state                    # running / not running

# 查看默认 zone
firewall-cmd --get-default-zone

# 查看所有 zone 及接口归属
firewall-cmd --get-active-zones

# 查看 public zone 完整配置
firewall-cmd --zone=public --list-all

# 查看某个接口当前归属 zone
firewall-cmd --get-zone-of-interface=eth0

# 查看所有 zone 的所有配置
firewall-cmd --list-all-zones
```

### 6.2 Zone 管理

```bash
# 修改默认 zone（新接口默认落到的 zone）
firewall-cmd --set-default-zone=trusted

# 给接口分配 zone（立即生效 + 持久化）
firewall-cmd --permanent --zone=internal --change-interface=eth1
firewall-cmd --reload

# 按源地址归属 zone（比接口更精确）
firewall-cmd --permanent --zone=trusted --add-source=192.168.1.0/24
firewall-cmd --reload
```

### 6.3 服务 / 端口 / 协议

```bash
# 服务（推荐，自动处理多端口）
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service={http,https}
firewall-cmd --permanent --zone=public --remove-service=http
firewall-cmd --get-services        # 查看所有可用服务名

# 端口（标准服务之外的场景）
firewall-cmd --permanent --zone=public --add-port=8080/tcp
firewall-cmd --permanent --zone=public --add-port=1000-2000/udp
firewall-cmd --permanent --zone=public --remove-port=8080/tcp

# 协议（非 TCP/UDP）
firewall-cmd --permanent --zone=public --add-protocol=icmp

# 源端口（限制"来自哪个源端口"，多用于防滥用）
firewall-cmd --permanent --zone=public --add-source-port=53/udp

# 限源：只允许特定网段访问某端口（通过富规则，见 6.5）
```

### 6.4 端口转发 / NAT（MASQUERADE）

```bash
# 1. 开启源 NAT（内网出网，external zone 默认已开）
firewall-cmd --permanent --zone=external --add-masquerade
firewall-cmd --permanent --zone=external --query-masquerade

# 2. 本机端口转发：80 → 8080
firewall-cmd --permanent --zone=public \
  --add-forward-port=port=80:proto=tcp:toport=8080

# 3. 转发到内网其他主机：8080 → 10.0.0.5:80
firewall-cmd --permanent --zone=public \
  --add-forward-port=port=8080:proto=tcp:toport=80:toaddr=10.0.0.5

# 4. 转发到内网主机同端口（仅写地址）
firewall-cmd --permanent --zone=public \
  --add-forward-port=port=8080:proto=tcp:toaddr=10.0.0.5

# 注意：跨 zone 的端口转发，可能需要同时放行目标 zone 的 FORWARD（用 direct 规则或 rich rule 处理，见排错节）
```

### 6.5 Rich Rule（富规则）——firewalld 的"高级语言"

当 zone/服务/端口表达不了需求时（限源、限时段、多条件组合），用富规则。富规则是 firewalld 对底层规则的**结构化封装**，比直接规则（direct）更安全、顺序更可控。

```bash
# 语法总纲
# rule [family="ipv4|ipv6"]
#      [source address="CIDR"] [destination address="CIDR"]
#      [service name="..."] | [port port="..." protocol="..."]
#      [icmp-block name="..."] [log [prefix="..."]] [audit]
#      [accept | reject | drop | mark set="..."]

# 示例 1：仅允许办公网段访问 SSH
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" source address="10.1.1.0/24" service name="ssh" accept'
firewall-cmd --reload

# 示例 2：拒绝某个 IP 访问 HTTP 并记日志
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" source address="1.2.3.4" service name="http" log prefix="HTTP_BLOCK " level=info drop'
firewall-cmd --reload

# 示例 3：限速（配合 limit）
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" service name="ssh" limit value="5/m" accept'
firewall-cmd --reload

# 示例 4：时段控制（仅工作日白天开放管理端口）
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" source address="10.1.1.0/24" port port="8443" protocol="tcp" time start="09:00" stop="18:00" accept'
firewall-cmd --reload

# 查看当前 zone 的全部富规则
firewall-cmd --zone=public --list-rich-rules
```

> 富规则有**优先级**概念（`priority` 属性，`--priority`，数值小的先匹配），冲突时按优先级而非添加顺序裁决，这在复杂策略下比 iptables 更可控。

### 6.6 Direct Rule（直接规则）——面向底层

直接规则让你把原生 iptables/nft 语法直接注入，绕过 zone 抽象。**生产环境应尽量避免**，仅用于 zone/rich 无法表达的边缘场景：

```bash
# 注入一条原生规则到 filter 表 INPUT 链（firewalld 内部链名见文档）
firewall-cmd --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 8080 -j ACCEPT
firewall-cmd --direct --remove-rule ipv4 filter INPUT 0 -p tcp --dport 8080 -j ACCEPT
firewall-cmd --direct --get-all-rules

# 永久化
firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 8080 -j ACCEPT
```

> 注意：firewalld 的 direct 规则挂在它自己的管理链中，`--reload` 时可能被重构，顺序依赖特定占位链（如 `INPUT_direct`），排错时用 `iptables-save` / `nft list ruleset` 确认实际位置。

### 6.7 其他运维操作

```bash
# 重载
firewall-cmd --reload            # 推荐：应用 permanent 到 runtime，不中断连接
firewall-cmd --complete-reload   # 完全重建，中断所有连接（慎用）

# 锁定（防止非 root 在本地改规则）
firewall-cmd --lockdown-on
firewall-cmd --lockdown-off

# 日志级别调整（排错时打开）
# 编辑 /etc/firewalld/firewalld.conf 中 LogDenied=all，然后 --reload

# 默认拒绝 ICMP 类型
firewall-cmd --permanent --zone=public --add-icmp-block=echo-request
```

---

## 7. 常见生产场景配置实战（双解法对照）

> 每一场景给出 iptables 与 firewalld 两种实现，生产环境按发行版选择其一，不要混用管理同一张规则集。

### 场景 1：SSH 白名单防护（只允许办公网段登录）

**firewalld（推荐现代方案）：**
```bash
# 将管理网段划入 trusted，其余入站 SSH 一律不放行
firewall-cmd --permanent --zone=trusted --add-source=10.1.1.0/24
firewall-cmd --permanent --zone=public --remove-service=ssh   # public 默认有 ssh，先移除
firewall-cmd --reload
# 或用富规则限定来源
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" source address="10.1.1.0/24" service name="ssh" accept'
firewall-cmd --reload
```

**iptables：**
```bash
iptables -P INPUT DROP
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -s 10.1.1.0/24 -j ACCEPT
iptables-save > /etc/sysconfig/iptables
```

### 场景 2：Web 服务器（Nginx 80/443 + 健康检查放行）

**firewalld：**
```bash
firewall-cmd --permanent --add-service=http --add-service=https
# 若健康检查需要特殊 ICMP/源
firewall-cmd --permanent --add-protocol=icmp
firewall-cmd --reload
```

**iptables：**
```bash
iptables -A INPUT -p tcp -m multiport --dports 80,443 -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
```

### 场景 3：NAT 网关（内网出外网 + 端口映射）

拓扑：eth1=内网(192.168.100.0/24)，eth0=外网(203.0.113.10)

**firewalld：**
```bash
# 内网接口划入 internal，外网接口划入 external（external 自带 masquerade）
firewall-cmd --permanent --zone=internal --change-interface=eth1
firewall-cmd --permanent --zone=external --change-interface=eth0
firewall-cmd --permanent --zone=external --add-masquerade
# 公网 80 端口映射到内网 web 服务器 10.0.0.5:80
firewall-cmd --permanent --zone=external \
  --add-forward-port=port=80:proto=tcp:toport=80:toaddr=10.0.0.5
# 允许内网→外网转发
firewall-cmd --permanent --zone=internal --add-masquerade
firewall-cmd --reload
# 内核转发
sysctl -w net.ipv4.ip_forward=1
```

**iptables：**
```bash
echo 1 > /proc/sys/net/ipv4/ip_forward
# 出网 SNAT
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o eth0 -j MASQUERADE
# 放行转发
iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o eth1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -P FORWARD DROP
# 端口映射 DNAT（含内网回包到 SNAT 的兼容处理）
iptables -t nat -A PREROUTING -d 203.0.113.10 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.5:80
iptables -t nat -A POSTROUTING -d 10.0.0.5 -p tcp --dport 80 -j SNAT --to-source 192.168.100.1
iptables-save > /etc/sysconfig/iptables
```

> **经典坑**：内网用户用公网 IP 访问自己的映射服务时"回不来"，原因是没有回程 SNAT（即最后那条 `POSTROUTING -d 10.0.0.5 ... -j SNAT --to-source 内网网关IP`），或缺少 hairpin NAT 支持。

### 场景 4：抗 SYN Flood / 连接洪水

**firewalld（rich rule 限速）：**
```bash
# 对 HTTP 新连接限速，超限丢弃
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" service name="http" limit value="20/s" accept'
firewall-cmd --reload
# 内核层
sysctl -w net.ipv4.tcp_syncookies=1
sysctl -w net.ipv4.tcp_syn_retries=2
sysctl -w net.ipv4.tcp_synack_retries=2
```

**iptables：**
```bash
iptables -A INPUT -p tcp --syn -m limit --limit 5/s --limit-burst 20 -j ACCEPT
iptables -A INPUT -p tcp --syn -j DROP
sysctl -w net.ipv4.tcp_syncookies=1
```

### 场景 5：临时/自动封禁攻击 IP（结合 fail2ban 或 ipset）

**firewalld（利用 rich rule 动态加）：**
```bash
# fail2ban 对接 firewalld 的 action 会生成类似规则：
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" source address="1.2.3.4" drop'
firewall-cmd --reload
# 解封
firewall-cmd --permanent --remove-rich-rule='rule family="ipv4" source address="1.2.3.4" drop'
```

**iptables（ipset 方案，批量高效）：**
```bash
ipset create attackers hash:ip timeout 600
iptables -I INPUT -m set --match-set attackers src -j DROP
# fail2ban 配置 ipset action 或脚本：ipset add attackers $IP
```

### 场景 6：仅开放管理网段访问数据库（3306）

**firewalld：**
```bash
firewall-cmd --permanent --zone=trusted --add-source=10.1.1.0/24
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" source address="10.1.1.0/24" port port="3306" protocol="tcp" accept'
firewall-cmd --reload
```

**iptables：**
```bash
iptables -A INPUT -p tcp --dport 3306 -s 10.1.1.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 3306 -j DROP
```

### 场景 7：堡垒机/跳板机限时段访问

```bash
# 富规则：工作日 09:00-18:00 才允许 SSH
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" service name="ssh" time start="09:00" stop="18:00" accept'
# 其余时段默认拒绝（public 中移除 ssh 服务即可）
firewall-cmd --permanent --zone=public --remove-service=ssh
firewall-cmd --reload
```

### 场景 8：透明代理重定向（REDIRECT）

```bash
# iptables：把本机 80 流量重定向到 3128（squid 透明代理）
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 3128
```

### 场景 9：Ping 洪水限速 + ICMP 管理

```bash
# firewalld
firewall-cmd --permanent --zone=public \
  --add-rich-rule='rule family="ipv4" protocol value="icmp" icmp-type name="echo-request" limit value="5/s" accept'
# iptables
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 5/s --limit-burst 10 -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-request -j DROP
```

---

## 8. 内核参数调优（与防火墙配套）

防火墙规则只是第一步，配合内核参数才能防住真正的攻击：

```bash
# /etc/sysctl.conf 关键项

# 转发开关（NAT/路由场景必开）
net.ipv4.ip_forward = 1

# 防 SYN Flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# 反地址欺骗（rp_filter=1，多网卡场景注意误伤）
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 连接跟踪表上限（NAT 高并发场景关键！）
net.netfilter.nf_conntrack_max = 1048576        # 按内存 128MB/万条估算
net.netfilter.nf_conntrack_buckets = 262144
# 查看当前使用量
# cat /proc/sys/net/netfilter/nf_conntrack_count

# 缩短异常连接占用 conntrack 的时间
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_udp_timeout_stream = 120

# TIME_WAIT 快速回收（注意：tcp_tw_recycle 已被内核移除，不要再配置）
net.ipv4.tcp_fin_timeout = 30
net.ipv4.ip_local_port_range = 1024 65535

# 应用后
sysctl -p
```

> **排错警示**：NAT 网关"连接一多就断/新连接建不上"时，先查 `nf_conntrack_count` 是否接近 `nf_conntrack_max`——这比查防火墙规则更常见。

---

## 9. 排错与调试方法论

### 9.1 标准排错流程

1. **确认防火墙本身状态**：
   ```bash
   systemctl status firewalld      # firewalld 场景
   iptables -L -n -v               # iptables 场景
   firewall-cmd --list-all
   ```
2. **确认包是否到达目标链**（看计数器）：
   ```bash
   iptables -L INPUT -n -v         # pkts 列是否在增长？
   watch -n1 'iptables -L INPUT -n -v'
   ```
3. **逐跳确认路由/转发**：
   ```bash
   ip route get 10.0.0.5
   ```
4. **抓包确认流量形态**（终极手段）：
   ```bash
   tcpdump -i eth0 -nn port 80
   tcpdump -i eth0 -nn 'tcp[tcpflags] & tcp-syn != 0'
   ```
5. **查看日志**：
   ```bash
   # iptables LOG 目标输出到 kern
   journalctl -k | grep -i "BLOCKED"
   # firewalld
   journalctl -u firewalld -f
   # 启用拒绝日志：firewalld.conf 中 LogDenied=all
   ```

### 9.2 高频故障与对策速查

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| 规则加了不生效，计数器为 0 | 包没走到这条链（如转发包写进了 INPUT） | 确认用 FORWARD；确认接口/地址匹配正确 |
| 端口转发不通 | NAT 表规则缺失或顺序错 | `iptables -t nat -L -n -v`；确认 `ip_forward=1` |
| NAT 转发出去能通，内网回不来 | 缺回程 SNAT / hairpin 未处理 | 加 `POSTROUTING -d 内网目标 -j SNAT --to-source 网关内网IP` |
| 重启后规则丢失 | 未持久化 | 用 iptables-save / iptables-services / netfilter-persistent |
| firewalld 改完不生效 | 没 `--reload`，或只加了 `--permanent` | `firewall-cmd --reload` |
| 高并发下新连接失败 | conntrack 表满 | 检查 `nf_conntrack_count`，调大 `nf_conntrack_max` |
| 用 iptables 改规则被 firewalld 覆盖 | 两者管理同一规则集冲突 | 二选一管理，别混用；新系统用 firewalld/nft |
| 某些服务多端口难放行 | 不了解服务定义 | 用 `firewall-cmd --add-service=服务名` 或自定义 services/*.xml |
| 内网 DHCP/DNS 被挡 | 未放行相应协议/UDP | 放行 dhcpv6-client 服务、53/udp 等 |

### 9.3 firewalld 与 iptables 混用排查建议

- `firewall-cmd --get-backend` 确认后端；
- `iptables-save` 与 `nft list ruleset` 对比，理解"你看到的是翻译层还是真实规则"；
- **结论：生产环境选定一种管理方式，另一套只做只读观测。**

---

## 10. 最佳实践与运维注意事项

### 10.1 通用安全原则

1. **默认拒绝，按需放行**：`-P INPUT DROP` / 使用低信任 zone，再逐个开放服务；
2. **最小权限**：能按源地址/网段限就限，不要对全世界开放管理端口；
3. **白名单优先**：管理类服务（SSH、数据库、监控）一律加源限制；
4. **规则顺序敏感**：iptables 是线性匹配，**先放行后拒绝**、先精确后宽泛；
5. **变更有备份、有回滚**：改前 `iptables-save`/导出 zone 文件，改后立即验证；
6. **远程操作纪律**：先在控制台/带外通道留好 rescue，避免把自己锁在门外（脚本里先 `-P ACCEPT` 再操作）。

### 10.2 firewalld 专项建议

- 用 **Zone 分层**而非堆规则：管理网→trusted、内网→internal、公网→public；
- 能用 **service** 不用 **port**（服务定义更可读、可复用）；
- 复杂策略用 **rich rule**，别碰 direct rule（除非别无选择）；
- 所有变更统一 `--permanent` + `--reload`，保持 runtime 与 permanent 一致；
- 定期 `firewall-cmd --list-all-zones` 做规则审计，清理废弃富规则。

### 10.3 iptables 专项建议

- 用自定义链组织规则（`-N`）提升可读性：
  ```bash
  iptables -N SSH_PROTECT
  iptables -A INPUT -p tcp --dport 22 -j SSH_PROTECT
  iptables -A SSH_PROTECT -m recent --name ssh --update --seconds 60 --hitcount 4 -j DROP
  iptables -A SSH_PROTECT -m recent --name ssh --set -j ACCEPT
  ```
- 大量封禁用 **ipset**，不要逐条写规则；
- 规则里加 `-m comment --comment "说明"`，半年后你还能读懂自己写的规则。

### 10.4 版本与生态趋势

- RHEL 9 / Rocky 9 / Alma 9：默认 **nftables + firewalld**，iptables 为兼容层；
- 新项目一律按 **nftables 语法与 firewalld 管理模型**来设计；
- 老系统（RHEL 6/7）仍广泛使用 iptables，迁移到新系统时注意**语法与命令差异**；
- 容器网络（docker/kubernetes）会动态插入大量 iptables/nft 规则，**不要与容器网桥接口上的规则冲突**，放行容器网段即可，别擅自 `-F`。

---

## 11. 附录：iptables ↔ firewalld 命令对照表

| 操作 | iptables | firewalld |
|------|----------|-----------|
| 查看当前规则 | `iptables -L -n -v` | `firewall-cmd --list-all` |
| 查看 NAT 规则 | `iptables -t nat -L -n -v` | `firewall-cmd --list-all --permanent` |
| 放行某端口 | `iptables -A INPUT -p tcp --dport 80 -j ACCEPT` | `firewall-cmd --permanent --add-port=80/tcp` |
| 放行某服务 | `iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT` | `firewall-cmd --permanent --add-service={http,https}` |
| 按源 IP 放行 | `iptables -A INPUT -s 10.0.0.0/8 -j ACCEPT` | `firewall-cmd --permanent --add-source=10.0.0.0/8` |
| 拒绝某 IP | `iptables -A INPUT -s 1.2.3.4 -j DROP` | `firewall-cmd --permanent --add-rich-rule='rule source address="1.2.3.4" drop'` |
| 端口转发 | `iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 10.0.0.5:80` | `firewall-cmd --permanent --add-forward-port=port=80:proto=tcp:toaddr=10.0.0.5:toport=80` |
| 源 NAT | `iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE` | `firewall-cmd --permanent --add-masquerade` |
| 限速 | `-m limit --limit 5/s` | `--add-rich-rule='... limit value="5/s" accept'` |
| 默认拒绝入站 | `iptables -P INPUT DROP` | 用 drop/block zone 或 `--set-default-zone=drop` |
| 保存/持久化 | `iptables-save > /etc/sysconfig/iptables` | `firewall-cmd --permanent ...` + `--reload`（自动落盘） |
| 重载配置 | `iptables-restore < 文件` | `firewall-cmd --reload` |
| 查看计数器 | `iptables -L -n -v` | 底层 `nft list ruleset` / `iptables-save` |

---

## 结语

- **选型建议**：新系统、多网卡、需动态管理 → firewalld（nftables 后端）；老系统、精细底层控制、纯脚本管理 → iptables。二者不要在同一张规则集上混写。
- **排错三问**：包到哪条链了（计数器）？命中哪条规则（LOG/rich rule log）？被谁丢掉（默认策略还是显式 DROP）？
- **维护三件套**：默认拒绝、最小权限、变更留痕。

掌握 Netfilter 的钩子模型与 conntrack 状态机，再配合 Zone 抽象，就同时拥有了"底层通透"与"高层可管理"两种能力——这正是一个高级 Linux 运维工程师应有的防火墙视角。

---

需要的话，我可以进一步为你：
- 输出一份可直接落地的**企业基线防火墙配置模板**（含 zone 规划、服务清单、审计脚本）；
- 写一套**防火墙规则变更审计 + 自动备份 + 回滚**的运维脚本；
- 或整理 **nftables 原生语法速查**，为迁移到 RHEL 9 做准备。

你更想先要哪一块？
