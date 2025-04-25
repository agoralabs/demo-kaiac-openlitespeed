#!/bin/bash


# Paramètres
DOMAIN="php.skyscaledev.com"
DOMAIN_FOLDER="phpmyadmin"
MYSQL_DB_HOST="dbols.skyscaledev.com"
PHP_VERSION="lsphp81"
ALB_TAG_NAME="Name"
ALB_TAG_VALUE="ols-alb-prod-lb"

# Variables dérivées
WEB_ROOT="/var/www/${DOMAIN_FOLDER}"
VHOST_CONF="/usr/local/lsws/conf/vhosts/${DOMAIN_FOLDER}/vhconf.conf"
HTTPD_CONF="/usr/local/lsws/conf/httpd_config.conf"
PMA_VERSION="5.2.1"
TOP_DOMAIN="skyscaledev.com"  # À adapter si nécessaire

# Fonctions
generate_secret() {
    openssl rand -base64 32 | head -c 32
}

create_dns_record() {
    AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
    HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$TOP_DOMAIN" --query "HostedZones[0].Id" --output text | cut -d'/' -f3)

    if [ -z "$HOSTED_ZONE_ID" ]; then
        echo "Zone hébergée pour $TOP_DOMAIN introuvable"
        return 1
    fi

    ALB_ARN=$(aws resourcegroupstaggingapi get-resources \
        --tag-filters "Key=$ALB_TAG_NAME,Values=$ALB_TAG_VALUE" \
        --resource-type-filters elasticloadbalancing:loadbalancer \
        --query "ResourceTagMappingList[0].ResourceARN" \
        --output text \
        --region $AWS_REGION)

    ALB_DNS_NAME=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --query "LoadBalancers[0].DNSName" \
        --output text \
        --region $AWS_REGION)

    TMP_FILE=$(mktemp)
    cat > "$TMP_FILE" <<EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "${DOMAIN}.",
            "Type": "CNAME",
            "TTL": 300,
            "ResourceRecords": [{ "Value": "${ALB_DNS_NAME}" }]
        }
    }]
}
EOF

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$HOSTED_ZONE_ID" \
        --change-batch "file://$TMP_FILE"
    rm -f "$TMP_FILE"

    echo "Enregistrement DNS ${DOMAIN} créé pointant vers ${ALB_DNS_NAME}"
}

# Début du déploiement
echo "=== Déploiement de phpMyAdmin ==="

# 1. Installation des dépendances
sudo apt-get update > /dev/null
sudo apt-get install -y ${PHP_VERSION} ${PHP_VERSION}-{common,mysqli,json,mbstring,zip,gd,curl} awscli > /dev/null

# 2. Configuration du dossier
sudo mkdir -p "${WEB_ROOT}"
sudo chown nobody:nogroup "${WEB_ROOT}"
sudo chmod 755 "${WEB_ROOT}"

# 3. Téléchargement phpMyAdmin
cd /tmp
wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.zip" -O pma.zip
unzip -q pma.zip
mv phpMyAdmin-${PMA_VERSION}-all-languages/* "${WEB_ROOT}"
rm -rf pma.zip phpMyAdmin-*

# 4. Configuration phpMyAdmin
cat > "${WEB_ROOT}/config.inc.php" <<EOL
<?php
\$cfg['blowfish_secret'] = '$(generate_secret)';
\$cfg['Servers'][1]['host'] = '${MYSQL_DB_HOST}';
\$cfg['Servers'][1]['compress'] = false;
\$cfg['Servers'][1]['AllowNoPassword'] = false;
\$cfg['ForceSSL'] = true;
\$cfg['PmaAbsoluteUri'] = 'https://${DOMAIN}/';
?>
EOL

# 5. Configuration OpenLiteSpeed
sudo mkdir -p "/usr/local/lsws/conf/vhosts/${DOMAIN_FOLDER}"

# Configuration du listener HTTP80 (si inexistant)
if ! grep -q "listener http80" "$HTTPD_CONF"; then
    sudo tee -a "$HTTPD_CONF" > /dev/null <<EOL

listener http80 {
    address                 *:80
    secure                  0
    map                     ${DOMAIN_FOLDER} ${DOMAIN}
}
EOL
fi

# Configuration du virtualhost
sudo tee "${VHOST_CONF}" > /dev/null <<EOL
docRoot                   \$VH_ROOT/
index  {
  useServer               0
  indexFiles              index.php
}

context / {
  location                \$VH_ROOT
  allowBrowse             1
  indexFiles              index.php

  extraHeaders            <<<END_extraHeaders
  X-Frame-Options SAMEORIGIN
  X-Content-Type-Options nosniff
  Content-Security-Policy "default-src 'self'"
  Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
  END_extraHeaders
}
EOL

# Ajout du virtualhost
sudo tee -a "$HTTPD_CONF" > /dev/null <<EOL

virtualhost ${DOMAIN_FOLDER} {
    vhRoot                  ${WEB_ROOT}
    configFile              ${VHOST_CONF}
    allowSymbolLink         1
    enableScript            1
    restrained              0
}
EOL

# Ajouter la règle map
if ! grep -q "map\s\+${DOMAIN_FOLDER}\s\+${DOMAIN}" "${HTTPD_CONF}"; then
    echo "Ajout de la règle map..."
    sudo sed -i "/listener http80\s*{/a \ \ map                     ${DOMAIN_FOLDER} ${DOMAIN}" "${HTTPD_CONF}"
fi

# 6. Redémarrage et configuration DNS
sudo systemctl restart lsws
create_dns_record

echo "=== Déploiement réussi ==="
echo "URL: https://${DOMAIN}"
echo "Répertoire: ${WEB_ROOT}"
echo "Connexion DB: ${MYSQL_DB_HOST}"
echo "======================================"