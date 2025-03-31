#!/bin/bash
set -e

# 1. Variables
EFS_DNS_NAME="fs-07b538683791e7aff.efs.us-west-2.amazonaws.com"
MOUNT_DIR="/mnt/efs"
EFS_PATH="$MOUNT_DIR/olsefs"

# 2. Créer le dossier de montage
mkdir -p $MOUNT_DIR

# 3. Monter EFS
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${EFS_DNS_NAME}:/ $MOUNT_DIR

# 4. (Optionnel) Vérifie qu’EFS est monté
if mountpoint -q $MOUNT_DIR; then
    echo "✅ EFS monté avec succès à $MOUNT_DIR"
else
    echo "❌ Échec du montage EFS"
    exit 1
fi

# 5. Refaire les liens symboliques
# Conf
if [ -L /usr/local/lsws/conf ]; then
  rm /usr/local/lsws/conf
elif [ -d /usr/local/lsws/conf ]; then
  mv /usr/local/lsws/conf /usr/local/lsws/conf.bak
fi
ln -sfn $EFS_PATH/conf /usr/local/lsws/conf

# WWW
if [ -L /var/www ]; then
  rm /var/www
elif [ -d /var/www ]; then
  mv /var/www /var/www.bak
fi
ln -sfn $EFS_PATH/www /var/www

# 6. Redémarrer OpenLiteSpeed (optionnel)
systemctl restart lsws || systemctl restart openlitespeed

echo "✅ Configuration terminée"
