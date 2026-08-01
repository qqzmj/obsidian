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
#创建用于VNC登录的用户，VNC不支持使用root用户
[root@192 ~]# usermod -aG wheel vncuser1
#将vncuser1加入到管理员组wheel()中

```