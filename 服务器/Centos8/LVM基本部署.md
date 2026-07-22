## LVM基本组成
![[Pasted image 20260722205312.png]]
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

```








