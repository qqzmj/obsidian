## 配置镜像加速
```
[root@localhost docker]# bash <(curl -sSL https://n3.ink/helper)
#配置docker镜像加速，以上为购买的毫秒镜像加速

[root@localhost docker]# systemctl daemon-reload 
[root@localhost docker]# systemctl restart docker
#重启使新的配置配置生效
```
## 拉取nginx镜像
```
[root@localhost docker]# docker pull nginx
#默认拉取最新版本镜像

[root@localhost docker]# docker images
REPOSITORY   TAG       IMAGE ID       CREATED       SIZE
nginx        latest    9f33606b3685   2 weeks ago   161MB
#查看已经拉取的docker镜像文件
```
## 创建宿主机挂载目录
```
[root@localhost ~]# mkdir -p /home/nginx/conf /home/nginx/log /home/nginx/html
#启动前需要先创建nginx外部挂载的配置文件（ /home/nginx/conf/nginx.conf）之所以要先创建 , 是因为Nginx本身容器只存/etc/nginx 目录 , 本身就不创建 nginx.conf 文件当服务器和容器都不存在 nginx.conf 文件时, 执行启动命令的时候 docker会将nginx.conf 作为目录创建 , 这并不是我们想要的结果
```









