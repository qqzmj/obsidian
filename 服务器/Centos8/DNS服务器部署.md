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
## 自定义正反向解析区域文件
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
### 内容参数讲解
```
A：即A记录，将域名映射到ipv4地址
AAAA：将域名映射到ipv6地址
PTR：反向DNS解析的记录类型

===============================================================

serial：序列号。主从DNS同步时，从服务器会比较这个数字来判断配置文件是否更新。数字越大代表越新
refresh：刷新时间。从服务器每个一条主动向主服务器询问一次是否有更新
retry：重试时间。如果主从同步失败，从服务器每隔1小时重新尝试一次
expire：过期时间。如果主服务器在1周内始终无法联系上，从服务器将放弃提供该区域的解析服务
minimum：最小TTL。用于负缓存（即查询不存在的域名时），告诉解析器最多缓存3小时
```
## 自定义DNS配置
### 正反向解析配置
#### named.rfc1912.zones文件
```
[root@localhost named]# cat /etc/named.rfc1912.zones 
// named.rfc1912.zones:
//
// Provided by Red Hat caching-nameserver package 
//
// ISC BIND named zone configuration for zones recommended by
// RFC 1912 section 4.1 : localhost TLDs and address zones
// and https://tools.ietf.org/html/rfc6303
// (c)2007 R W Franks
// 
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//
// Note: empty-zones-enable yes; option is default.
// If private ranges should be forwarded, add 
// disable-empty-zone "."; into options
// 

zone "localhost.localdomain" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
};

zone "localhost" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
};

zone "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
};

zone "1.0.0.127.in-addr.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
};

zone "0.in-addr.arpa" IN {
        type master;
        file "named.empty";
        allow-update { none; };
};


zone "baidu.com" IN {
        type master;
        #定义区域角色，这里说明这台DNS服务器是该区域的主服务器
        file "baidu.com.forward";
	    #区域文件存放位置及名称，存放位置我没有更改所以是默认/var/named
        allow-update { none; };
        #禁止动态更新，不允许任何客户端通过动态更新
};

zone "aliyun.com" IN {
        type master;
        file "aliyun.com.forward";
        allow-update { none; };
};

zone "qq.com" IN {
        type forward;
        forwarders { 223.5.5.5; };
        forward only;
};
```
### 区域配置文件
```
[root@localhost named]# ll named.localhost 
-rw-r-----. 1 root named 152 Aug 25  2021 named.localhost
[root@localhost named]# ll named.loopback 
-rw-r-----. 1 root named 168 Aug 25  2021 named.loopback
#正向区域文件默认权限属性，一定要保持一致，否则服务无法启动

[root@localhost named]# cp -a named.localhost baidu.com.forward
[root@localhost named]# cp -a named.localhost aliyun.com.forward
[root@localhost named]# cp -a named.localhost qq.com.forward
[root@localhost named]# cp -a named.localhost weibo.com.forwar
#直接复制原有正向区域文件进行修改，-a或者-p保证权限和属性不变
#文件名称需要跟named.rfc1912.zones文件里面定义的file名称一致

[root@localhost named]# ll | grep com
-rw-r-----. 1 root  named  166 Jul 24 15:25 aliyun.com.forward
-rw-r-----. 1 root  named  395 Jul 24 17:45 baidu.com.forward
-rw-r-----. 1 root  named  166 Jul 24 15:25 qq.com.forward
-rw-r-----. 1 root  named  166 Jul 24 15:25 weibo.com.forward
#查看权限是否正确

[root@localhost named]# cat weibo.com.forward 
$TTL 1D
@       IN SOA  @ rname.invalid. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
        NS      weibo.com.
weibo.com.      A       111.13.134.130
[root@localhost named]# cat aliyun.com.forward 
$TTL 1D
@       IN SOA  @ rname.invalid. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
        NS      aliyun.com.
aliyun.com.      A       140.205.135.3
[root@localhost named]# cat baidu.com.forward 
$TTL 1D
@       IN SOA  @ rname.invalid. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
        NS      baidu.com.
baidu.com.      A       182.61.200.110
[root@localhost named]# cat qq.com.forward 
$TTL 1D
@       IN SOA  @ rname.invalid. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
        NS      qq.com.
qq.com.      A       112.60.14.252
#上面是相关域名的正向配置

[root@localhost named]# named-checkconf
[root@localhost named]# named-checkzone qq.com /var/named/qq.com.forward 
zone qq.com/IN: loaded serial 0
OK
[root@localhost named]# named-checkzone baidu.com /var/named/baidu.com.forward 
zone baidu.com/IN: loaded serial 0
OK
[root@localhost named]# named-checkzone weibo.com /var/named/weibo.com.forward 
zone weibo.com/IN: loaded serial 0
OK
[root@localhost named]# named-checkzone aliyun.com /var/named/aliyun.com.forward 
zone aliyun.com/IN: loaded serial 0
OK
#对named配置文件和区域文件进行语法检查，避免语法错误导致服务无法启动

[root@localhost named]# systemctl restart named
#重启服务生效
[root@localhost named]# rndc reload
server reload successful
#重加载也可以生效，这个不会断业务，是热加载，重启服务是冷加载会断业务

```







