#!/bin/bash
# Désactivation LSCache pour un seul site WordPress
# Usage : sudo ./disable_lscache_single.sh /chemin/vers/votre/site

WEB_ROOT="$1"

if [ -z "$WEB_ROOT" ]; then
    echo "❌ Spécifiez le chemin du site WordPress :"
    echo "Usage : $0 /chemin/vers/site"
    exit 1
fi

echo "=== Désactivation LSCache pour $WEB_ROOT ==="

# 1. Désactiver le plugin via WP-CLI
if [ -f "${WEB_ROOT}/wp-config.php" ]; then
    echo "Désactivation du plugin..."
    sudo -u www-data wp plugin deactivate litespeed-cache --path="$WEB_ROOT"
    
    # 2. Supprimer les règles .htaccess spécifiques
    echo "Nettoyage du .htaccess..."
    HTACCESS="${WEB_ROOT}/.htaccess"
    if [ -f "$HTACCESS" ]; then
        sudo sed -i '/<IfModule LiteSpeed>/,/<\/IfModule>/d' "$HTACCESS"
        sudo sed -i '/LiteSpeed/d' "$HTACCESS"
    fi
    
    # 3. Purger le cache existant
    echo "Purging residual cache..."
    sudo rm -rf "${WEB_ROOT}/wp-content/litespeed/"
else
    echo "❌ wp-config.php introuvable - vérifiez le chemin"
    exit 1
fi

echo "✅ Désactivation terminée pour ${WEB_ROOT}"
echo "Note : Aucun redémarrage serveur nécessaire (modifications locales uniquement)"