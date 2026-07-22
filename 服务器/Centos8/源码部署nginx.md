## 下载nginx二进制源码包
```
cd /root
mkdir -p /root/nginx
wget -P /root/nginx https://nginx.org/download/nginx-1.26.3.tar.gz
mkdir /nginx
tar -zxvf nginx安装包 -C /nginx    
#解压到指定目录，找到解压后的README文件，查看安装方法，网站内documentation的Building from Sources
```
## 安装前环境配置
```
[root@localhost nginx-1.26.3]# ./configure --help
#带with的是默认不安装的，带without是默认已经安装了的。可以选择配置专门管理nginx的用户以提升安全性，也可以不配置使用默认的root用户进行管理

yum install -y gcc gcc-c++
#编译器安装
```
![[Pasted image 20260722202411.png]]
```
#上面图片中带PATH的是相应文件默认存放路径，可以设置也可以不设置（默认在根下面）。以上所有参数根据需要进行添加。
```

---

## 指定源码安装目录和需要的模块
```
[root@localhost nginx-1.26.3]# ./configure --prefix=/opt/nginx --with-http_mp4_module 
#指定源码安装目录、安装mp4模块。后续会提示相关报错，HTTP重写需要PCRE库。

[root@localhost nginx-1.26.3]# yum list all | grep -i pcre
#查看是否存在pcre包

[root@localhost nginx-1.26.3]# yum -y install pcre-devel pcre
#安装pcre

[root@localhost nginx-1.26.3]# ./configure --prefix=/opt/nginx --with-http_mp4_module 
#重新进行安装，查看是否存在报错
./configure: error: the HTTP gzip module requires the zlib library.
#提示HTTP gzip模块需要zlib库

[root@localhost nginx-1.26.3]# yum install -y zlib-devel zlib
#安装zlib

[root@localhost nginx-1.26.3]# ./configure --prefix=/opt/nginx --with-http_mp4_module 
Configuration summary
#重新进行安装，查看是否存在报错
```
## nginx源码编译及安装
```
[root@localhost nginx-1.26.3]# lscpu
#查看cpu数量

[root@localhost nginx-1.26.3]# make -j 4
#运行4个cpu进行编译，必须在源码文件夹下进行

[root@localhost nginx-1.26.3]# make install
#该步骤为真正的nginx安装，必须在源码文件夹下进行
make[1]: Leaving directory `/opt/nginx/nginx-1.26.3'

[root@localhost nginx]# ls
conf  html  logs  nginx-1.26.3  sbin
#nginx-1.26.3是解压目录，忽略。conf（配置）、html（网页）、logs（日志）、sbin（程序）

[root@localhost sbin]# ./nginx
#运行nginx
```
## nginx环境变量及服务配置
```
[root@localhost ~]# vim .bash_profile 
#编辑环境变量文件，增加nginx软件路径（用户级配置文件为~/.bash_profile或~/.bashrc）
PATH=/opt/nginx/sbin:$PATH:$HOME/bin

[root@localhost ~]#  source /root/.bash_profile 
[root@localhost ~]# nginx -s stop
#关闭nginx

[root@localhost ~]# nginx
#启动nginx

[root@localhost ~]# nginx -s reload
#重加载nginx
#如果需要开机自启动可以写在开机脚本里面

[root@localhost ~]# cat /etc/rc.d/rc.local 
#开机脚本路径
#在文件内添加相关命令即可，”nginx“添加后即可开机自启动了
```
## 将源码nginx创建成服务进行管理(可选)
```
[root@localhost ~]# cd /usr/lib/systemd/system
#所有服务均在该目录下

[root@localhost system]# cp -a vsftpd.service nginx.service
#vsftpd的服务文件跟nginx很类似，用来改比较方便，这里直接复制粘贴进行修改即可

[root@localhost system]# vim nginx.service 
	[Unit]
	Description=nginx web daemon
	#描述名称
	After=network.target

	[Service]
	Type=forking
	ExecStart=/opt/nginx/sbin/nginx
	#启动目录

	[Install]
	WantedBy=multi-user.target
	
[root@localhost system]# systemctl daemon-reload
#重新加载
[root@localhost ~]# systemctl restart nginx
#需要先关闭之前运行的nginx服务才可以启动

[root@localhost ~]# systemctl enable nginx
```
## 防火墙放行服务端口


