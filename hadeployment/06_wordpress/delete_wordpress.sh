#!/bin/bash

# Paramètres
DOMAIN="$1"
DOMAIN_FOLDER="$2"
MYSQL_DB_HOST="$3"
WP_DB_NAME="$4"
MYSQL_ROOT_USER="$5"
MYSQL_ROOT_PASSWORD="$6"
RECORD_NAME="$7" # provient du message SQS
TOP_DOMAIN="$8" # provient du message SQS
WP_SFTP_USER="$9" # provient du message SQS

# Variables
WP_SFTP_REMOVE_USER_SCRIPT="/home/ubuntu/remove_sftp_user.sh"

# 1. Supprimer la base de données
mysql -h "${MYSQL_DB_HOST}" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_SCRIPT
DROP DATABASE IF EXISTS ${WP_DB_NAME};
DROP USER IF EXISTS '${WP_DB_NAME}_usr'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# 2. Supprimer les fichiers
rm -rf "/var/www/${DOMAIN_FOLDER}"

# 3. Supprimer la configuration OpenLiteSpeed
rm -rf "/usr/local/lsws/conf/vhosts/${DOMAIN_FOLDER}"
sed -i "/virtualhost ${DOMAIN_FOLDER}/,/^}/d" /usr/local/lsws/conf/httpd_config.conf
sed -i "/map \+${DOMAIN_FOLDER} \+${DOMAIN}/d" /usr/local/lsws/conf/httpd_config.conf

# 4. Redémarrer OpenLiteSpeed
systemctl restart lsws

# Variables AWS
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$TOP_DOMAIN" --query "HostedZones[0].Id" --output text | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "Zone hébergée pour le domaine $TOP_DOMAIN introuvable"
    exit 1
fi

# Fonction pour supprimer l'enregistrement DNS
delete_record() {
    # Récupérer l'enregistrement existant pour vérification
    EXISTING_RECORD=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --query "ResourceRecordSets[?Name == '$RECORD_NAME.$TOP_DOMAIN.' && Type == 'CNAME']" \
        --output json)

    if [ "$EXISTING_RECORD" = "[]" ]; then
        echo "L'enregistrement $RECORD_NAME.$TOP_DOMAIN n'existe pas. Rien à supprimer."
        exit 0
    fi

    # Créer le fichier JSON pour la suppression
    TMP_FILE=$(mktemp)
    cat > "$TMP_FILE" <<EOF
{
    "Comment": "Suppression de l'enregistrement $RECORD_NAME.$TOP_DOMAIN",
    "Changes": [
        {
            "Action": "DELETE",
            "ResourceRecordSet": {
                "Name": "$RECORD_NAME.$TOP_DOMAIN",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "$(echo "$EXISTING_RECORD" | jq -r '.[0].ResourceRecords[0].Value')"
                    }
                ]
            }
        }
    ]
}
EOF

    # Appliquer les changements DNS
    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "file://$TMP_FILE"

    # Nettoyer le fichier temporaire
    rm -f "$TMP_FILE"

    echo "Enregistrement DNS $RECORD_NAME.$TOP_DOMAIN supprimé"
}


delete_record

# Supprimer l'utilisateur SFTP
if [ -f "$WP_SFTP_REMOVE_USER_SCRIPT" ]; then
    $WP_SFTP_REMOVE_USER_SCRIPT "$WP_SFTP_USER"
else
    echo "Le script de suppression de l'utilisateur SFTP $WP_SFTP_REMOVE_USER_SCRIPT n'est pas présent."
fi

# Supprimer le repertoire des logs
rm -rf "/usr/local/lsws/logs/vhosts/${DOMAIN_FOLDER}"

echo "Suppression de ${DOMAIN} terminée"