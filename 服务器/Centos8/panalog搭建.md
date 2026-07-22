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
/usr/logd/bin/logd &
#如果解压到/目录则如上
#比如解压到/panalog/中，则/panalog/usr/logd/bin/logd &
```