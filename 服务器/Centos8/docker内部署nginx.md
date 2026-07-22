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

[root@localhost docker]# docker images REPOSITORY TAG IMAGE ID CREATED SIZE nginx latest 9f33606b3685 2 weeks ago 161MB
#查看已经拉取的docker镜像文件
```










