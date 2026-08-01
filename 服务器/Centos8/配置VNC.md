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
A view-only password is not used


```