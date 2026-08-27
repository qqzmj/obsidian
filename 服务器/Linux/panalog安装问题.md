Centos8.5安装panabit注意事项：
====================
## 1、软件使用的是c7依赖库，c8不兼容需重新安装
dnf install -y ncurses-compat-libs libnsl compat-openssl10
#安装系统依赖库

## 2、解决lib18的依赖项无法找到问题
ls -l /usr/lib64/mysql/libmysqlclient.so.18
#显示符号链接指向 libmysqlclient_r.so.18.1.0，且目标文件存在
echo "/usr/lib64/mysql" > /etc/ld.so.conf.d/mysql-lib.conf
ldconfig
#添加库目录到系统搜索路径
ldd /usr/logd/bin/logd | grep mysqlclient
#验证依赖是否已解析
**<font color="#c00000">不建议用centos8，建议centos7.9，centos8虽然搭建成功但是功能性有问题</font>**