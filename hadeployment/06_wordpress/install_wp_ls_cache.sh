#!/bin/bash
# Installe LiteSpeed Cache + active le cache

# Vérifier les paramètres
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <web_root>"
    exit 1
fi

WEB_ROOT="$1"

cd $WEB_ROOT  # Adaptez le chemin
wp plugin install litespeed-cache --activate
wp option update litespeed-cache-conf '[{"_id":"cache","enabled":"1"}]' --format=json
echo "LSCache installé et activé !"