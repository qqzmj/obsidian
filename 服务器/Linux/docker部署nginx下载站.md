## 创建nginx容器
```
[root@c7_1 ~]# docker run -d --name xzz1 -p 9999:80 nginx
50de50bd3cde4db1d7e300f6d221a7948a9d219e0f9621ad9b64ea0ec5a244e1
[root@c7_1 ~]# docker ps
CONTAINER ID   IMAGE     COMMAND                  CREATED              STATUS              PORTS                                   NAMES
50de50bd3cde   nginx     "/docker-entrypoint.…"   About a minute ago   Up About a minute   0.0.0.0:9999->80/tcp, :::9999->80/tcp   xzz1
```
## 下载站根目录创建
```
[root@c7_1 ~]# docker exec -it xzz1 /bin/bash
root@50de50bd3cde:/# mkdir xxz_share
root@50de50bd3cde:/# ls | grep xxz
xxz_share
```
## nginx文件修改
```
[root@c7_1 ~]# docker cp xzz1:/etc/nginx/nginx.conf ~/
Successfully copied 2.56kB to /root/
[root@c7_1 ~]# docker cp xzz1:/etc/nginx/conf.d/default.conf ~/
Successfully copied 3.07kB to /root/
[root@c7_1 ~]# ll | grep nginx
-rw-r--r--. 1 root root    644 Jul 16 00:25 nginx.conf
[root@c7_1 ~]# ll | grep default
-rw-r--r--. 1 root root   1093 Aug 12 11:49 default.conf

[root@c7_1 ~]# vim default.conf 
server {
      listen       80 default_server;
      listen       [::]:80 default_server;
      server_name  localhost;

      location / {
          root /xxz_share;
          autoindex on;
          autoindex_exact_size off;
          autoindex_localtime on;
          charset utf-8;
          sub_filter 'Index of /' '自用下载站';
          sub_filter_once off;
          if (-f $request_filename) 
             {
              add_header Content-Disposition 'attachment'; 
             }
                 }
         }
         
[root@c7_1 ~]# docker cp ~/default.conf xzz1:/etc/nginx/conf.d/
Successfully copied 3.58kB to xzz1:/etc/nginx/conf.d/
[root@c7_1 ~]# docker cp ~/nginx.conf xzz1:/etc/nginx/
Successfully copied 2.56kB to xzz1:/etc/nginx/

```
## 文件上传至下载站目录
```

```