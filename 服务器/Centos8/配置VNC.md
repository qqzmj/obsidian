## 安装桌面环境
```
[root@192 ~]# dnf groupinstall "Server with GUI" -y
#安装“带图形界面的服务器”这一整套软件组，groupinstall是软件组安装
[root@192 ~]# systemctl set-default graphical.target 
#启用系统图形模式
[root@192 ~]# reboot
#重启生效
```
## 安装VNC软件
```
[root@192 ~]# dnf install tigervnc-server tigervnc-server-module -y
```