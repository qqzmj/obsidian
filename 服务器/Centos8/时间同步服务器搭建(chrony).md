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
## 检查是否成功
```
[root@localhost ~]# chronyc sources -v

  .-- Source mode  '^' = server, '=' = peer, '#' = local clock.
 / .- Source state '*' = current best, '+' = combined, '-' = not combined,
| /             'x' = may be in error, '~' = too variable, '?' = unusable.
||                                                 .- xxxx [ yyyy ] +/- zzzz
||      Reachability register (octal) -.           |  xxxx = adjusted offset,
||      Log2(Polling interval) --.      |          |  yyyy = measured offset,
||                                \     |          |  zzzz = estimated error.
||                                 |    |           \
MS Name/IP address         Stratum Poll Reach LastRx Last sample               
===============================================================================
^- 1.82.219.234                  3   6    13     1    -54ms[  -54ms] +/-  182ms
^? 218.241.118.143               0   8     0     -     +0ns[   +0ns] +/-    0ns
^* 203.107.6.88                  2   6    77     8   +252us[+1635us] +/-   21ms

============================参数解释
MS Name/IP address
	M：时间源模式
		^ server（服务器）
		= peer（对等体）
		# local clock（本地时钟）
	S：源状态
		* 当前正在使用的最佳源
		+ 可接受的源
		- 被排除的源
		x 可能有错误
		~ 变化太大
		? 不可用

Stratum
	0 = 原子钟/GPS等原始时钟源
	1 = 直接连接0层时钟的服务器
	2 = 从1层服务器同步（常见公共NTP）
	3-15 = 逐级向下传递
	16 = 未同步状态
	#正常状态下不会出现0
	
Poll
	表示多久查询一次这个时间源，以2的次方计算，如2的6次方秒
============================参数解释
```




