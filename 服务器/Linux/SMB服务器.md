## 关闭安全相关
```
systemctl stop firewalld
systemctl disable firewalld
setenforce 0
vim /etc/sysconfig/selinux
```
## 安装SMB服务
```
yum install -y samba samba-client
systemctl start smb
systemctl enable smb
cp -a /etc/samba/smb.conf /etc/samba/smb.conf.bak #备份配置文件
```
## 创建用户
```
useradd smbuser1
passwd smbuser1
smbpasswd -a smbuser1
```
## 创建共享目录
```
mkdir -p /SMBshare
chmod -R 777 SMBshare/  #更改文件夹权限
chown -R smbuser;smbuser SMBshare/  #更改文件夹属主

vim /etc/samba/smb.conf  #新增配置
	[public]
		comment = 用户
		path = /SMBshare
		public = yes
		writable = yes
		
```