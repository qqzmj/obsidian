## 安装Xfce桌面和TigerVNC
```
dnf -y groupinstall "Xfce"
dnf -y install tigervnc-server dbus-x11
```
## 创建VNC用户
```
useradd -m -s /bin/bash vncuser1
#创建vncuser1，创建家目录、使用登录shell为/bin/bash
passwd vncuser1
```
## 设置VNC密码
```
mkdir -p /home/vncuser1/.vnc
chown vncuser1:vncuser1 /home/vncuser1/.vnc
chmod 700 /home/vncuser1/.vnc
#root用户下执行上述
su - vncuser1 -c "vncpasswd"
```

