## 清理系统自有docker
```
[root@localhost ~]# sudo yum remove docker \
 > docker-client \
 > docker-client-latest \
 > docker-common \
 > docker-latest \
 > docker-latest-logrotate \
 > docker-logrotate \
 > docker-engine #删除旧版本docker，无论有没有都建议执行一遍
```