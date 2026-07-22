## LVM基本组成
![[Pasted image 20260722205312.png]]
<font color="#c00000">扩容无风险，缩减风险大。非必要不缩容</font>
## 查看硬盘信息及当前挂载信息
```
[root@192 ~]# lsblk
NAME        MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sr0          11:0    1 10.1G  0 rom  
nvme0n1     259:0    0   30G  0 disk 
├─nvme0n1p1 259:1    0    1G  0 part /boot
└─nvme0n1p2 259:2    0   29G  0 part 
  ├─cl-root 253:0    0   27G  0 lvm  /
  └─cl-swap 253:1    0    2G  0 lvm  [SWAP]
nvme0n2     259:3    0  100G  0 disk 
nvme0n3     259:4    0  100G  0 disk 
#nv**2和3是我们新增的100G硬盘

[root@192 ~]# df -h
Filesystem           Size  Used Avail Use% Mounted on
devtmpfs             877M     0  877M   0% /dev
tmpfs                896M     0  896M   0% /dev/shm
tmpfs                896M  8.7M  887M   1% /run
tmpfs                896M     0  896M   0% /sys/fs/cgroup
/dev/mapper/cl-root   27G  3.0G   24G  11% /
/dev/nvme0n1p1      1014M  216M  799M  22% /boot
tmpfs                179M     0  179M   0% /run/user/0
#可以看到我们新增的硬盘没有挂载，这就不会影响系统以及数据。这种情况下才可以进行操作，否则影响系统
```
## 创建PV（物理卷）
```
[root@192 ~]# pvcreate /dev/nvme0n2 
  Physical volume "/dev/nvme0n2" successfully created.
[root@192 ~]# pvcreate /dev/nvme0n3
  Physical volume "/dev/nvme0n3" successfully created.
#将硬盘初始化为LVM的物理卷，不支持两个硬盘一起初始化

[root@192 ~]# pvs
  PV             VG Fmt  Attr PSize   PFree  
  /dev/nvme0n1p2 cl lvm2 a--  <29.00g      0 
  /dev/nvme0n2      lvm2 ---  100.00g 100.00g
  /dev/nvme0n3      lvm2 ---  100.00g 100.00g
#查看pv简要信息，详细信息使用pvdisplay
```
## 创建VG（卷组）并将PV加入到VG
```
[root@192 ~]# vgcreate vg1 /dev/nvme0n2 /dev/nvme0n3
  Volume group "vg1" successfully created
#将硬盘加入到名称vg1的VG卷组中

[root@192 ~]# vgs
  VG  #PV #LV #SN Attr   VSize   VFree  
  cl    1   2   0 wz--n- <29.00g      0 
  vg1   2   0   0 wz--n- 199.99g 199.99g
```
## 创建LV（逻辑卷）
```
[root@192 ~]# lvcreate -l 100%FREE -n lv1 vg1
  Logical volume "lv1" created.
#-n指定逻辑卷名称
#创建一个名为lv1的逻辑卷，调用vg1卷组的空间，使用vg1所有空间
#lvcreate -L 199.99G -n lv1 vg1，这是自定义大小的方式

[root@192 ~]# lvs
  LV   VG  Attr       LSize   Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
  root cl  -wi-ao----  26.96g                                                    
  swap cl  -wi-ao----   2.03g                                                    
  lv1  vg1 -wi-a----- 199.99g   
```
## 格式化并挂载
```
[root@192 ~]# mkfs.xfs /dev/vg1/lv1
[root@192 ~]# mkdir -p /panalog/logdata
[root@192 ~]# mount /dev/vg1/lv1 /panalog/logdata
#将lv1格式化为xfs格式，创建挂载目录，将lv挂载到目录上

[root@192 ~]# xfs_growfs /dev/vg1/lv1
#xfs_growfs是xfs格式的在线扩容工具，resize2fs是ext系列在线扩容工具

[root@192 ~]# blkid | grep lv1
/dev/mapper/vg1-lv1: UUID="7f758be4-7b53-4c23-9e3a-517907eb2586" BLOCK_SIZE="512" TYPE="xfs"
#查看lv的UUID，用于开机自动挂载

[root@192 ~]# vi /etc/fstab 
	UUID=7f758be4-7b53-4c23-9e3a-517907eb2586 /panalog/logdata xfs defaults 0 0
#写入fstab文件以实现开机自动挂载

[root@192 ~]# mount -a 
#全部重新挂载

[root@192 ~]# df -h | grep lv1
/dev/mapper/vg1-lv1  200G  1.5G  199G   1% /panalog/logdata
#查看是否挂载成功

=================注意=======================
ext4最大文件大小16TB、最大文件系统大小1EB、支持在线缩减空间、支持在线扩容
xfs最大文件大小8EB、最大文件系统大小8EB、不支持在线缩减空间、支持在线扩容
=================注意=======================
```







