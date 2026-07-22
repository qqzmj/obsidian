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
```

