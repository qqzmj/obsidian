## 安装相关软件
```
[root@localhost ~]# yum install -y bind bind-utils bind-chroot
#bind，dns主软件；bind-utils，dns工具包，用于调试之类的；bind-chroot，dns安全机制，提供chroot隔离运行环境
```
## Cache-only DNS配置
```
[root@localhost ~]# vim /etc/named.conf
	listen-on port 53 { any; };
	allow-query     { any; };
	#允许所有人进行访问和查询
	forward only;
    forwarders {
                119.29.29.29;
                223.5.5.5;
                };
#修改并增加cache-only配置
	dnssec-enable no;
    dnssec-validation no;
    #session-keyfile "/run/named/session.key";
#关闭dnssec，取消检查根密钥文件。不这样做会出现dnssec验证问题，导致无法解析

[root@localhost ~]# named-checkconf 
#检查配置文件语法

[root@localhost ~]# systemctl start named
[root@localhost ~]# systemctl enable named
#启动并配置自启动named服务

[root@localhost ~]# firewall-cmd --permanent --add-service=dns
success
#放行dns服务
[root@localhost ~]# firewall-cmd --reload
success
#重加载防火墙配置
[root@localhost ~]# firewall-cmd --list-all
#查看防火墙规则
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: ens160
  sources: 
  services: cockpit dhcpv6-client dns ssh
  ports: 
  protocols: 
  forward: no
  masquerade: no
  forward-ports: 
  source-ports: 
  icmp-blocks: 
  rich rules: 
```
![[named.conf]]
上面是修改后的文件
## 转发器配置

```
[root@localhost ~]# vim /etc/named.conf
	zone "baidu.com"{
	        type forward;
	        forward only;
	        forwarders { 114.114.114.114; };
	};
	
	zone "aliyun.com"{
	        type forward;
	        forward only;
	        forwarders { 114.114.114.114; };
	};

[root@localhost ~]# tcpdump -i any -n port 53 and host 114.114.114.114
#抓包验证
dropped privs to tcpdump
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on any, link-type LINUX_SLL (Linux cooked v1), capture size 262144 bytes
14:01:37.633403 IP 192.168.73.11.54174 > 114.114.114.114.domain: 60856+% [1au] A? baidu.com. (66)
14:01:37.637757 IP 114.114.114.114.domain > 192.168.73.11.54174: 60856 2/5/12 A 182.61.200.108, A 182.61.200.110 (412)
14:01:48.308822 IP 192.168.73.11.55292 > 114.114.114.114.domain: 8026+% [1au] A? aliyun.com. (67)
14:01:48.332518 IP 114.114.114.114.domain > 192.168.73.11.55292: 8026 6/3/13 A 106.11.253.83, A 106.11.248.146, A 140.205.135.3, A 106.11.172.9, A 140.205.60.46, A 106.11.249.99 (445)
```
![[named 1.conf]]
以上为修改后的配置文件
## 自定义正反向解析
### 正向解析区域文件示例
```
[root@localhost named]# cat named.localhost
$TTL 1D
@       IN SOA  @ rname.invalid. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
        NS      @
        A       127.0.0.1
        AAAA    ::1
```

### 反向解析区域文件示例
```
[root@localhost named]# cat named.loopback 
$TTL 1D
@       IN SOA  @ rname.invalid. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
        NS      @
        A       127.0.0.1
        AAAA    ::1
        PTR     localhost.
```











