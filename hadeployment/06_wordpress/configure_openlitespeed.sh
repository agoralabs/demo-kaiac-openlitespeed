#!/bin/bash

# Vérification des arguments
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 [DOMAIN] [DOMAIN_FOLDER] [WEB_ROOT] [HTTPD_CONF] [VHOST_CONF]"
    echo "Exemple: $0 ..."
    exit 1
fi

DOMAIN="$1"
DOMAIN_FOLDER="$2"
WEB_ROOT="$3"
HTTPD_CONF="$4"
VHOST_CONF="$5"

# Configurer OpenLiteSpeed
echo "Configuration d'OpenLiteSpeed..."

# Configurer le listener http80 si nécessaire
if ! grep -q "listener http80 {" "${HTTPD_CONF}"; then
    echo "Ajout du listener http80..."
    sudo tee -a "${HTTPD_CONF}" > /dev/null <<EOL

# BEGIN WordPress listener
listener http80 {
    address                 *:80
    secure                  0
}
# END WordPress listener
EOL
fi

# Créer le répertoire du virtual host
sudo mkdir -p "/usr/local/lsws/conf/vhosts/${DOMAIN_FOLDER}"

# Créer la configuration du virtual host
echo "Configuration du virtual host..."
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

  rewrite  {
    enable                1
    inherit               1
    rewriteFile           /var/www/${DOMAIN_FOLDER}/.htaccess
  }
}

rewrite  {
  enable                  1
  autoLoadHtaccess        1
}
EOL

# Ajouter le virtualhost à la configuration principale
if ! grep -q "virtualhost ${DOMAIN_FOLDER}" "${HTTPD_CONF}"; then
    echo "Ajout du virtualhost..."
    sudo tee -a "${HTTPD_CONF}" > /dev/null <<EOL

# BEGIN WordPress virtualhost
virtualhost ${DOMAIN_FOLDER} {
    vhRoot                  ${WEB_ROOT}
    configFile              ${VHOST_CONF}
    allowSymbolLink         1
    enableScript            1
    restrained              0
}
# END WordPress virtualhost
EOL
fi

# Ajouter la règle map
if ! grep -q "map\s\+${DOMAIN_FOLDER}\s\+${DOMAIN}" "${HTTPD_CONF}"; then
    echo "Ajout de la règle map..."
    sudo sed -i "/listener http80\s*{/a \ \ map                     ${DOMAIN_FOLDER} ${DOMAIN}" "${HTTPD_CONF}"
fi