#!/bin/bash

# Step 1: Install NFS Client
sudo apt-get update
sudo apt-get -y install nfs-common

# Exemple: créer un point de montage local
sudo mkdir -p /mnt/efs

# Monter manuellement
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport fs-07b538683791e7aff.efs.us-west-2.amazonaws.com:/ /mnt/efs

# creer le repertoire conf
sudo mkdir -p /mnt/efs/olsefs/conf

# creer le repertoire www
sudo mkdir -p /mnt/efs/olsefs/www

# Copier les configs
sudo cp -r /usr/local/lsws/conf /mnt/efs/olsefs

# Copier les sites wordpress
sudo cp -r /var/www /mnt/efs/olsefs


#Modifier OpenLiteSpeed pour utiliser EFS
#Sur l'instance (ou ton AMI), crée un lien symbolique vers EFS :

sudo mv /usr/local/lsws/conf /usr/local/lsws/conf.bak
sudo ln -s /mnt/efs/olsefs/conf /usr/local/lsws/conf


sudo mv /var/www /var/www.bak
sudo ln -s /mnt/efs/olsefs/www /var/www


#sudo cp -r /usr/local/lsws/conf.bak/* /mnt/efs/olsefs/conf
#sudo cp -r /var/www.bak/* /mnt/efs/olsefs/www  