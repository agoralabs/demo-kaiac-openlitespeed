#!/bin/bash
set -e

# Variables configurables

MOUNT_DIR="/mnt/efs"
EFS_PATH="$MOUNT_DIR/olsefs"
REGION="us-west-2"
s3_bucket="kaiac.agoralabs.org"
s3_key="olsefs_archive.zip"
TAG_KEY="Name"          # Remplacez par votre clé de tag
TAG_VALUE="efsols"  # Remplacez par votre valeur de tag


# Fonction pour récupérer le nom DNS d'un volume EFS à partir de ses tags
get_efs_dns_from_tag() {
    local efs_id
    
    
    # Récupération de l'ID EFS
    efs_id=$(aws efs describe-file-systems \
        --region $REGION \
        --query "FileSystems[?Tags[?Key=='${TAG_KEY}' && Value=='${TAG_VALUE}']].FileSystemId" \
        --output text)
    
    # Vérification du résultat
    if [ -z "$efs_id" ]; then
        echo "Aucun volume EFS trouvé avec le tag ${TAG_KEY}=${TAG_VALUE}" >&2
        exit 1
    fi
    
    # Construction du DNS EFS
    efs_dns="${efs_id}.efs.${REGION}.amazonaws.com"
    
    echo "$efs_dns"  # Sortie pour capture dans d'autres scripts
}

# Appel de la fonction

EFS_DNS_NAME=$(get_efs_dns_from_tag)

# Step 1: Install NFS Client on db EC2
sudo apt-get update
sudo apt-get -y install nfs-common

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
#elif [ -d /usr/local/lsws/conf ]; then
#  mv /usr/local/lsws/conf /usr/local/lsws/conf.bak
fi
ln -sfn $EFS_PATH/conf /usr/local/lsws/conf

# WWW
if [ -L /var/www ]; then
  rm /var/www
#elif [ -d /var/www ]; then
#  mv /var/www /var/www.bak
fi
ln -sfn $EFS_PATH/www /var/www

# Configurer EFS correctement
sudo chown -R lsadm:lsadm /usr/local/lsws/conf
sudo chmod -R 775 /usr/local/lsws/conf

# 6. Redémarrer OpenLiteSpeed (optionnel)
systemctl restart lsws || systemctl restart openlitespeed

echo "✅ Configuration terminée"
