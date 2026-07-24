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
	
	forward only;
        forwarders {
                        119.29.29.29;
                        223.5.5.5;
                   };
[root@localhost ~]# named-checkconf 
```




