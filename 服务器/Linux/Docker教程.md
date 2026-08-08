### 启动容器
docker run <>
	--name=<> #指定本容器名称
	-d #后台运行本容器并返回容器ID，同时启动守护式容器
	-i #以交互模式运行容器，通常与-t同时使用
	-t #为容器重新分配一个伪输入中断，通常与-i同时使用
	-p <宿主机端口>:<容器端口> #指定端口映射
	-P #随机端口映射
```
root@user1-U1:~# docker run -d --name nginx1 -it -p 9090:80 nginx:latest 
2f1f179cdfd83339a4ccafc95109df2a69c0abfad2da59a9cb1727566dc62330
root@user1-U1:~# netstat -tunlp | grep 9090
tcp        0      0 0.0.0.0:9090            0.0.0.0:*               LISTEN      27164/docker-proxy  
tcp6       0      0 :::9090                 :::*                    LISTEN      27172/docker-proxy  
```
## 容器导入导出镜像


```
[root@localhost ~]# docker run -d -it --name vmc1 centos:8
35957d6510c27099179628d47e07df106476bbd925be3bd334a8eaf03fa00f4a
[root@localhost ~]# docker ps
CONTAINER ID   IMAGE      COMMAND       CREATED         STATUS         PORTS     NAMES
35957d6510c2   centos:8   "/bin/bash"   4 seconds ago   Up 3 seconds             vmc1
[root@localhost ~]# docker export 35957d6510c2 > ~/vmc1.tar
[root@localhost ~]# ll -a | grep vmc1
-rw-r--r--.  1 root root 238571520 Aug  8 15:49 vmc1.tar
[root@localhost ~]# docker kill vmc1
vmc1
[root@localhost ~]# docker rm -f vmc1
vmc1
[root@localhost ~]# docker ps 
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
[root@localhost ~]# docker import - vm1 < ~/vmc1.tar
sha256:c684bc6e5a38513e712200480566272228f5ca8b3d2e891aa33af8b9148c9010
[root@localhost ~]# docker ps
CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
[root@localhost ~]# docker images
REPOSITORY    TAG       IMAGE ID       CREATED         SIZE
vm1           latest    c684bc6e5a38   7 seconds ago   231MB
[root@localhost ~]# docker run -d -it --name myvm1 vm1 /bin/bash
bac39aeaa709ef3539b079397a18e530418fcf68c9328fa33ac507f6fcf95e54
[root@localhost ~]# docker exec -it myvm1 /bin/bash
[root@bac39aeaa709 /]# ls
bin  etc   lib    lost+found  mnt  proc  run   srv  tmp  var
dev  home  lib64  media       opt  root  sbin  sys  usr
```