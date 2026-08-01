## 安装桌面环境
```
[root@192 ~]# dnf groupinstall "Server with GUI" -y
#安装“”
[root@192 ~]# systemctl set-default graphical.target 
[root@192 ~]# reboot

```