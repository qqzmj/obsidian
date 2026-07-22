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
## 配置运行panalog
```
/usr/logd/bin/logd &
#如果解压到/目录则如上
#比如解压到/panalog/中，则/panalog/usr/logd/bin/logd &

chmod +x /etc/rc.d/rc.local
systemctl start rc-local
systemctl enable rc-local
vim /etc/rc.d/rc.local
	/usr/logd/bin/logd &
#给rc.local添加执行权限，并且启动rc服务。在rc.local中添加开机自动执行的命令，就达到了开机自启动panalog服务的功能
```
