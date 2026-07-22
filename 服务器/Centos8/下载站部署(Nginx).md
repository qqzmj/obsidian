## 安装并启动nginx
```
yum install -y nginx
#安装nginx

systemctl start nginx
systemctl enable nginx
#配置自启动nginx服务
```
## 创建用于共享的目录
```
mkdir -p /datadir
```
## 修改nginx配置文件
```
[root@192 centos-ios]# cat /etc/nginx/nginx.conf
# For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/
#   * Official Russian Documentation: http://nginx.org/ru/docs/

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Load modular configuration files from the /etc/nginx/conf.d directory.
    include /etc/nginx/conf.d/*.conf;

    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  _;
        root         /usr/share/nginx/html;

        include /etc/nginx/default.d/*.conf;

        location / {
        }

        error_page 404 /404.html;
            location = /40x.html {
        }

        error_page 500 502 503 504 /50x.html;
            location = /50x.html {
        }
    }
=============================================需添加内容
    server {
        listen       8080 default_server;
        listen       [::]:8080 default_server;
        server_name  localhost;

        location / {
            root /datadir;
            autoindex on;
            autoindex_exact_size off;
            autoindex_localtime on;
            charset utf-8;
            sub_filter 'Index of /' '自用下载站';
            sub_filter_once off;
            if (-f $request_filename) {
                add_header Content-Disposition 'attachment';
        }
#这个if块用于只对文件添加http响应头，实现点击文件即可下载，访问目录之类的不会触发下载
    }
}}

```



