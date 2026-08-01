## 安装桌面环境
```
[root@192 ~]# dnf groupinstall "Server with GUI" -y
#安装“带图形界面的服务器”这一整套软件组，groupinstall是软件组安装
[root@192 ~]# systemctl set-default graphical.target 
#启用系统图形模式
[root@192 ~]# reboot
#重启生效
```
## VNC配置
```
[root@192 ~]# dnf install tigervnc-server tigervnc-server-module -y
#安装VNC软件
======================
[root@192 ~]# useradd -m vncuser1
#创建用于VNC登录的用户(-m创建家目录)，VNC不支持使用root用户
[root@192 ~]# usermod -aG wheel vncuser1
#将vncuser1加入到管理员组wheel(组ID:10)中
[root@192 ~]# su - vncuser1
#切换到实际需要使用VNC登录的用户
[vncuser1@192 ~]$ vncpasswd 
#修改当前用户VNC登录密码
Password:
Verify:
Would you like to enter a view-only password (y/n)? n
#询问是否额外设置只读密码
#y，使用只读密码，仅观看（画面同步，但所有按键和点击无效）
#n，不适用只读密码，完全控制（鼠标、键盘、复制粘贴、关机）
A view-only password is not used
======================
[vncuser1@192 system]$ su - root
Password: 
[root@192 ~]# cd /etc/systemd/system/
[root@192 system]# vim vncserver@.service
#创建vncserver@.service文件
[root@192 system]# cat vncserver@.service 
#以下是需要写入的配置内容
[Unit]
Description=Remote Desktop VNC Service
After=syslog.target network.target

[Service]
Type=forking
WorkingDirectory=/home/vncuser1
User=vncuser1
Group=vncuser1

ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill %i > /dev/null 2>&1 || :'
ExecStart=/usr/bin/vncserver -autokill %i
ExecStop=/usr/bin/vncserver -kill %i

[Install]
WantedBy=multi-user.target


```