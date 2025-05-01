#!/bin/bash
# Installe LiteSpeed Cache + active le cache

# Vérifier les paramètres
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <web_root>"
    exit 1
fi

WEB_ROOT="$1"

cd $WEB_ROOT  # Adaptez le chemin
wp plugin install litespeed-cache --activate --allow-root
wp option update litespeed-cache-conf '[{"_id":"cache","enabled":"1"}]' --format=json --allow-root
echo "LSCache installé et activé !"

# curl -I https://site1.skyscaledev.com | grep x-litespeed-cache