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




