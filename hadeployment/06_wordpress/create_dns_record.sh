#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 [DOMAIN] [DOMAIN_FOLDER] [WEB_ROOT] [HTTPD_CONF] [VHOST_CONF]"
    echo "Exemple: $0 ..."
    exit 1
fi

RECORD_NAME="$1"
TOP_DOMAIN="$2"
ALB_TAG_NAME="$3"
ALB_TAG_VALUE="$4"

echo "Création du record DNS pour le domaine $DOMAIN..."

# Variables AWS
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$TOP_DOMAIN" --query "HostedZones[0].Id" --output text | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "Zone hébergée pour le domaine $TOP_DOMAIN introuvable"
    exit 1
fi

# Trouver l'ARN de l'ALB basé sur le tag
ALB_ARN=$(aws resourcegroupstaggingapi get-resources \
    --tag-filters "Key=$ALB_TAG_NAME,Values=$ALB_TAG_VALUE" \
    --resource-type-filters elasticloadbalancing:loadbalancer \
    --query "ResourceTagMappingList[0].ResourceARN" \
    --output text \
    --region $AWS_REGION)

if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
    echo "ALB avec le tag $ALB_TAG_NAME=$ALB_TAG_VALUE introuvable"
    exit 1
fi

# Récupérer le DNS name de l'ALB
ALB_DNS_NAME=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query "LoadBalancers[0].DNSName" \
    --output text \
    --region $AWS_REGION)

if [ -z "$ALB_DNS_NAME" ]; then
    echo "Impossible de récupérer le DNS name pour l'ALB $ALB_ARN"
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