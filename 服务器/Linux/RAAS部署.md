```
tar -zxvf RAAS2.0-Free_HUANGSHANr1_20260828_Linux.inst
systemctl stop firewalld
systemctl disable firewalld
setenfore 0
#解压安装包，关闭安全措施
cd /RAAS2.0-Free_HUANGSHANr1_20260828_Linux/
 ./ipeinstall
#没有单独磁盘的情况下不要选择为/usr/panalog使用单独磁盘，数据会全部清除
#部署服务
touch /etc/systemd/system/raas.service
sudo cat > /etc/systemd/system/raas.service << 'EOF'
[Unit]
Description=RaaS Service
After=network.target

[Service]
Type=forking
User=root
Group=root
ExecStart=/usr/panabit/bin/ipectrl start all
ExecStop=/usr/panabit/bin/ipectrl stop
ExecReload=/usr/panabit/bin/ipectrl restart
# 这里使用 ipectrl stat 来查询状态
ExecStartPost=/usr/ramdisk/bin/ipectrl stat
# PIDFile=/var/run/raas.pid
‘# 如果服务进程会生成 PID 文件，请在这里指定路径
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
#将RAAS写入服务进行管理
systemctl restart raas
systemctl enable raas
#启动并配置开机自启动服务
```
