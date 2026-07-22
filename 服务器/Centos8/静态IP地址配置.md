
**<font color="#c00000">注意：centos8以下如果要使用NetworkManager进行管理需要先关闭network服务，避免两者冲突。8及以上没有network服务，无需关心</font>**

## NetworkManager方式
```
[root@localhost ~]# nmcli connection modify ens160 ipv4.method manual ipv4.addresses 192.168.11.10/24 ipv4.gateway 192.168.11.123 ipv4.dns "192.168.11.123,223.5.5.5" autoconnect yes
#IP获取方式为手工，开机自动启动网卡

[root@localhost ~]# nmcli connection down ens160 
[root@localhost ~]# nmcli connection up ens160
#重新激活网卡使配置生效
```
## 修改配置文件方式
```
vim /etc/sysconfig/network-scripts/ifcfg-ens160
TYPE=Ethernet
PROXY_METHOD=none 
BROWSER_ONLY=no 
BOOTPROTO=static 
#更改为静态配置地址 
DEFROUTE=yes 
IPV4_FAILURE_FATAL=no 
IPV6INIT=yes 
IPV6_AUTOCONF=yes 
IPV6_DEFROUTE=yes 
IPV6_FAILURE_FATAL=no 
IPV6_ADDR_GEN_MODE=stable-privacy 
NAME=ens33 UUID=你的UUID 
DEVICE=ens33 
ONBOOT=yes 
#是否开机自启动网卡 
===================================
# 以下为静态IP相关配置 
IPADDR=192.168.1.100 
# 静态IP地址 
NETMASK=255.255.255.0 
# 子网掩码 
GATEWAY=192.168.1.1 
# 网关 
DNS1=8.8.8.8 
# 首选DNS 
DNS2=114.114.114.114 
# 备用DNS（可选）
```
