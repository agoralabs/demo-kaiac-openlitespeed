#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 [DOMAIN] [DOMAIN_FOLDER] [WEB_ROOT] [HTTPD_CONF] [VHOST_CONF]"
    echo "Exemple: $0 ..."
    exit 1
fi

DOMAIN_CATEGORY=="$1"
RECORD_NAME="$2"
TOP_DOMAIN="$3"
ALB_DNS_NAME="$4"

if [ "$DOMAIN_CATEGORY" = "declared" ]; then
    echo "Pas de création du record DNS pour le domaine $TOP_DOMAIN..."
    exit 0
fi

echo "Création du record DNS pour le domaine $TOP_DOMAIN..."

# Variables AWS
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$TOP_DOMAIN" --query "HostedZones[0].Id" --output text | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "Zone hébergée pour le domaine $TOP_DOMAIN introuvable"
    exit 1
fi

# Créer le fichier JSON pour la modification DNS
TMP_FILE=$(mktemp)
cat > "$TMP_FILE" <<EOF
{
    "Comment": "Création de l'enregistrement $RECORD_NAME.$TOP_DOMAIN",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$RECORD_NAME.$TOP_DOMAIN",
                "Type": "CNAME",
                "TTL": 300,
                "ResourceRecords": [
                    {
                        "Value": "$ALB_DNS_NAME"
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

echo "Enregistrement DNS $RECORD_NAME.$TOP_DOMAIN créé/modifié pour pointer vers $ALB_DNS_NAME"