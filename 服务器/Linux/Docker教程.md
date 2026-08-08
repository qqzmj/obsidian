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
## 容器导入导出
