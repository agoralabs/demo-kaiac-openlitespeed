# Vérification du montage de l'EFS

D'abord se connecter en SSH à l'instance EC2 contenant la base de données

```
ssh -i "/root/.ssh/id_rsa" ubuntu@dbols.skyscaledev.com
```

```
root@ip-10-0-101-180:/home/ubuntu# df -h
```

```
Filesystem                                          Size  Used Avail Use% Mounted on
/dev/root                                            20G  3.1G   17G  16% /
tmpfs                                               959M  148K  959M   1% /dev/shm
tmpfs                                               384M  892K  383M   1% /run
tmpfs                                               5.0M     0  5.0M   0% /run/lock
efivarfs                                            128K  3.8K  120K   4% /sys/firmware/efi/efivars
/dev/nvme0n1p15                                     105M  6.1M   99M   6% /boot/efi
fs-08bb4e701bb292e38.efs.us-west-2.amazonaws.com:/  8.0E     0  8.0E   0% /mnt/efs
tmpfs                                               192M  4.0K  192M   1% /run/user/1000
```

# Vérification de l'initialisation des fichiers à partir de l'archive S3

```
root@ip-10-0-101-180:/home/ubuntu# ls -la /mnt/efs/olsefs/
```

```
total 16
drwxrwxrwx 4 root root 6144 Mar 30 22:19 .
drwxr-xr-x 3 root root 6144 Mar 31 11:18 ..
drwxrwxrwx 5 root root 6144 Mar 31 11:27 conf
drwxrwxrwx 2 root root 6144 Mar 31 11:27 www
```

# Durées

```
End of the Composition demolition.

3) MODULE bkshellremote DESTROY DURATION : 1m:6s
2) MODULE awsefsvolume DESTROY DURATION : 1m:39s
1) MODULE bkclustsg DESTROY DURATION : 1m:6s
TOTAL DEMOLITION DURATION : 4m:3s
```