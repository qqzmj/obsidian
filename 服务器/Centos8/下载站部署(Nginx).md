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
            #指定哪个目录作为http服务器的根目录
            autoindex on;
            #开启目录索引功能，即允许列出整个目录
            autoindex_exact_size off;
            #on，能够显示出文件的确切大小，单位是bytes
            #off，显示文件大概大小，单位是kB/MB/GB，该方式更为人性化
            autoindex_localtime on;
            #默认为off，显示的文件时间为GMT时间。改为on后，显示的文件时间为文件的服务器时间
            charset utf-8;
            #编码类型，如果出现乱码则改为gbk尝试
            sub_filter 'Index of /' '自用下载站';
            #修改标题
            sub_filter_once off;
            #控制文本替换的次数，这将会控制页面中所有出现“Index of /”都替换为“自用下载站”，如果设置为on，则只会替换第一次出现的位置
            if (-f $request_filename) {
                add_header Content-Disposition 'attachment';
        }
#这个if块用于只对文件添加http响应头，实现点击文件即可下载，访问目录之类的不会触发下载

=============================================需添加内容
    }
}}
```
## 关闭防火墙和selinux

**<font color="#c00000">配置完响应头后，如果出现无法点击下载，则可能是浏览器问题。建议更换浏览器测试，可以尝试360浏览器。</font>**


