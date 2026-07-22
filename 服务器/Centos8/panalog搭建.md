## 关闭安全措施
```
systemctl stop firewalld
systemctl disable firewalld
setenforce 0
vim /etc/sysconfig/selinux
	SELINUX=disabled
```
## 解压panalog原始文件
```
tar -zxvf loginstall20220513_Linux3.10.0x_amd64.tar.gz -C /
#解压到哪里可以随意
```
## 运行panalog
```

```