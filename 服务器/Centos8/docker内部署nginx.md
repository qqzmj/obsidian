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
#默认只需要挂这三个目录就够了
#启动前需要先创建nginx外部挂载的配置文件（ /home/nginx/conf/nginx.conf）之所以要先创建 , 是因为Nginx本身容器只存/etc/nginx 目录 , 本身就不创建 nginx.conf 文件当服务器和容器都不存在 nginx.conf 文件时, 执行启动命令的时候 docker会将nginx.conf 作为目录创建 , 这并不是我们想要的结果
```
## 创建临时nginx容器拷贝原始数据内容
```
[root@localhost ~]# mkdir -p /home/nginx/conf /home/nginx/log /home/nginx/html
#启动前需要先创建nginx外部挂载的配置文件（ /home/nginx/conf/nginx.conf）之所以要先创建 , 是因为Nginx本身容器只存/etc/nginx 目录 , 本身就不创建 nginx.conf 文件当服务器和容器都不存在 nginx.conf 文件时, 执行启动命令的时候 docker会将nginx.conf 作为目录创建 , 这并不是我们想要的结果。
[root@localhost nginx]# docker run --name nginx1 -p 9001:80 -d nginx
#创建并启动容器，名称为nginx1，将容器内80端口映射到宿主机上的9001端口，-d分离模式(后台运行)，nginx(镜像名称)
edae5e52a9a39566687fa9a23dfb08bf898dcfafda2f2029b67deb4a66bda9fe
[root@localhost nginx]# docker ps -a
CONTAINER ID   IMAGE     COMMAND                  CREATED          STATUS          PORTS                                   NAMES
edae5e52a9a3   nginx     "/docker-entrypoint.…"   22 seconds ago   Up 21 seconds   0.0.0.0:9001->80/tcp, :::9001->80/tcp   nginx1
[root@localhost nginx]# docker exec -it nginx1 /bin/bash
#进入名称nginx1的容器的内部
[root@localhost nginx]# docker cp nginx1:/etc/nginx/nginx.conf /home/nginx/conf/nginx.conf && docker cp nginx1:/etc/nginx/conf.d /home/nginx/conf/conf.d && docker cp nginx1:/usr/share/nginx/html /home/nginx/
Successfully copied 2.56kB to /home/nginx/conf/nginx.conf
Successfully copied 3.58kB to /home/nginx/conf/conf.d
Successfully copied 4.1kB to /home/nginx/
#将容器内nginx文件复制到宿主机的目录下
```








