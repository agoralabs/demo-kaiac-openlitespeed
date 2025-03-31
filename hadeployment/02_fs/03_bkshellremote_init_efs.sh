#!/bin/bash

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
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS_DNS_NAME:/ $MOUNT_DIR

sudo rm -rf /tmp/archive.zip

#sudo rm -rf ${MOUNT_DIR}/conf
#sudo rm -rf ${MOUNT_DIR}/www

# Télécharger l'archive depuis S3
sudo aws s3 cp s3://${s3_bucket}/${s3_key} /tmp/archive.zip --region ${REGION}

# Décompresser dans EFS avec override
sudo unzip -o /tmp/archive.zip -d ${MOUNT_DIR}/

# Nettoyer
sudo rm /tmp/archive.zip

#sudo umount $MOUNT_DIR
