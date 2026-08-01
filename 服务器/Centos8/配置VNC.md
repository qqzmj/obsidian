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
su - vncuser1 -c "vncpasswd"
#root用户下执行上述
```
## 配置Xfce桌面启动文件
```
cat > /home/vncuser1/.vnc/xstartup << 'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
chown vncuser1:vncuser1 /home/vncuser1/.vnc/xstartup
chmod 755 /home/vncuser1/.vnc/xstartup
#root用户下执行上述
```
## 配置systemd管理VNC服务
```
cat > /etc/systemd/system/vncserver@.service << 'EOF'
[Unit]
Description=VNC Server for %I
After=syslog.target network.target

[Service]
Type=forking
User=vncuser1
Group=vncuser1
WorkingDirectory=/home/vncuser1
ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill %i >/dev/null 2>&1 || :'
ExecStart=/usr/bin/vncserver %i -geometry 1280x720 -depth 24 -localhost no
ExecStop=/usr/bin/vncserver -kill %i

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now vncserver@:1
#重新加载 systemd 并启用、启动 VNC
#这里的 `:1` 表示显示编号 1，对应端口 `5901'
```
## 配置防火墙
```
firewall-cmd --permanent --add-port=5901/tcp
firewall-cmd --reload
setenforce 0
vim /etc/sysconfig/selinux
```
## 验证是否成功
```
systemctl status vncserver@:1 --no-pager
ss -lntp | grep 5901
cat /home/vncuser1/.vnc/*:1.log
#查看VNC日志是否有错误
#此时可以连接，在主机通过VNC工具IP:5901即可连接
```