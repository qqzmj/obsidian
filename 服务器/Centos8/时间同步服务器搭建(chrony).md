## 安装chrony
版本8以下默认是NTP，版本8及以上都默认使用的是chrony没有NTP
## 修改chrony配置文件
```
[root@localhost ~]# rpm -ql chrony | grep conf
/etc/chrony.conf
/etc/sysconfig/chronyd
/usr/share/man/man5/chrony.conf.5.gz
#查看chrony配置文件位置

[root@localhost etc]# cp -a chrony.conf chrony.conf.backup
#对配置文件进行备份，防止误操作

[root@localhost etc]# vi /etc/chrony.conf
server ntp.ntsc.ac.cn iburst
server ntp.cnnic.cn iburst
server ntp.aliyun.com iburst
#上游NTP服务器
allow 0.0.0.0/0
#允许所有网段访问同步，也可以直接用all
makestep 1.0 3
#在系统启动后的前 3次 时间更新中，如果时间偏差超过 1.0秒，直接跳变时间（而非慢慢调整）
maxupdateskew 100.0
#允许的最大时钟频率偏差为 100.0 ppm（百万分之一）
driftfile /var/lib/chrony/drift
#记录系统时钟的固有频率偏差到文件中
logdir /var/log/chrony
#指定chrony日志文件的存储目录
log measurements statistics tracking
#指定要记录哪些类型的日志
rtcsync
#定期将系统时间同步到硬件时钟（RTC - Real Time Clock）
local stratum 10
#即使上游不可达，也作为时间服务器
```