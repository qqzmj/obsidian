## 配置镜像加速
```
[root@localhost docker]# bash <(curl -sSL https://n3.ink/helper)
#配置docker镜像加速，以上为购买的毫秒镜像加速

[root@localhost docker]# systemctl daemon-reload 
[root@localhost docker]# systemctl restart docker
#重启使新的配置配置生效
```











