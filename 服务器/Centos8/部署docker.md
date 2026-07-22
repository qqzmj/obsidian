## 清理系统自有docker
```
[root@localhost ~]# sudo yum remove docker \
 > docker-client \
 > docker-client-latest \
 > docker-common \
 > docker-latest \
 > docker-latest-logrotate \
 > docker-logrotate \
 > docker-engine 
 #删除旧版本docker，无论有没有都建议执行一遍
```
## 安装docker本体和相关组件
```
[root@localhost ~]# sudo yum install -y yum-utils device-mapper-persistent-data lvm2
#YUM 扩展工具集，device-mapper-persistent-data 和 lvm2 用于管理 Docker 的存储驱动（devicemapper）

[root@localhost ~]# yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
#添加软件源信息（阿里云）

[root@localhost ~]# sudo yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
#安装docker

[root@localhost ~]# systemctl start docker
#启动docker

[root@localhost ~]# systemctl status docker
#Active：active (running)，说明docker已经启动

[root@localhost ~]# docker --version
#查看docker版本信息
Docker version 26.1.4, build 5650f9b
#至此docker就已经成功在系统中部署，可以进行后续使用
```














