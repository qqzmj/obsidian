## NetworkManager方式
```
user1@user1-VMware20-1:~$ sudo apt-get install network-manager
#安装NetworkManager服务

user1@user1-VMware20-1:~$ systemctl status NetworkManager ● NetworkManager.service - Network Manager Loaded: loaded (/usr/lib/systemd/system/NetworkManager.service; enabled; preset: enabled) Active: active (running) since Tue 2026-07-21 01:29:14 CST; 5min ago
#查看服务状态

user1@user1-VMware20-1:~$ sudo nmcli connection modify netplan-ens33 ipv4.method manual ipv4.addresses 192.168.73.111/24 ipv4.gateway 192.168.73.1 ipv4.dns "223.5.5.5,192.168.73.111" autoconnect yes
#配置方式跟centos一样

user1@user1-VMware20-1:~$ sudo nmcli connection down netplan-ens33 
user1@user1-VMware20-1:~$ sudo nmcli connection up netplan-ens33
#重新激活网卡连接使配置生效
```
## 修改配置文件方式
```
vim /etc/netplan/配置文件 更改配置文件如下： 
dhcp4: false 
#false为关闭自动获取，true为开启自动获取 
address: 
 - 10.0.0.1/24 
  #配置IP地址及掩码 
routes: 
 - to: default 
  via: 10.0.0.254 
  #配置网关及是否作为默认路由，default为默认路由器 
  nameservers:
   addresses: [8.8.8.8,223.5.5.5] 
  #配置DNS地址，用逗号间隔 
  netplan apply 
  #应用配置文件 
  systemctl restart systemd-networkd 
  #重启网卡服务 注意：不可以使用制表符，严格使用空格进行缩进。若文件格式错误则应用时会提示，导致无法成功应用配置
```
