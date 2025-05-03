#!/bin/bash
# Script pour activer ou désactiver LiteSpeed Cache pour un site WordPress
# Usage: ./toggle_lscache.sh [on|off] [site_name]
# Exemple: ./toggle_lscache.sh on site1_skyscaledev_com

# Vérifier les paramètres
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [on|off] [site_name]"
    echo "Exemple: $0 on site1_skyscaledev_com"
    exit 1
fi

ACTION="$1"
SITE_NAME="$2"
WEB_ROOT="/var/www/$SITE_NAME"

# Vérifier que le répertoire existe
if [ ! -d "$WEB_ROOT" ]; then
    echo "❌ Le répertoire $WEB_ROOT n'existe pas."
    echo "Vérifiez le nom du site."
    exit 1
fi

# Vérifier que c'est un site WordPress
if [ ! -f "${WEB_ROOT}/wp-config.php" ]; then
    echo "❌ wp-config.php introuvable dans $WEB_ROOT"
    echo "Vérifiez que c'est bien un site WordPress."
    exit 1
fi

# Fonction pour activer LSCache
activate_lscache() {
    echo "=== Activation de LSCache pour $SITE_NAME ==="
    cd $WEB_ROOT
    
    # Vérifier si le plugin est déjà installé
    if wp plugin is-installed litespeed-cache --allow-root; then
        echo "Plugin LiteSpeed Cache déjà installé, activation..."
        wp plugin activate litespeed-cache --allow-root
    else
        echo "Installation et activation du plugin LiteSpeed Cache..."
        wp plugin install litespeed-cache --activate --allow-root
    fi
    
    # Configurer le cache
    wp option update litespeed-cache-conf '[{"_id":"cache","enabled":"1"}]' --format=json --allow-root
    
    echo "✅ LSCache installé et activé pour $SITE_NAME !"
    echo "Vérifiez avec: curl -I https://$SITE_NAME | grep x-litespeed"
}

# Fonction pour désactiver LSCache
deactivate_lscache() {
    echo "=== Désactivation de LSCache pour $SITE_NAME ==="
    
    # Désactiver le plugin via WP-CLI
    echo "Désactivation du plugin..."
    wp plugin deactivate litespeed-cache --path="$WEB_ROOT" --allow-root
    
    # Supprimer les règles .htaccess spécifiques
    echo "Nettoyage du .htaccess..."
    HTACCESS="${WEB_ROOT}/.htaccess"
    if [ -f "$HTACCESS" ]; then
        sed -i '/<IfModule LiteSpeed>/,/<\/IfModule>/d' "$HTACCESS"
        sed -i '/LiteSpeed/d' "$HTACCESS"
    fi
    
    # Purger le cache existant
    echo "Suppression du cache résiduel..."
    rm -rf "${WEB_ROOT}/wp-content/litespeed/"
    
    echo "✅ LSCache désactivé pour $SITE_NAME"
}

# Exécuter l'action demandée
case "$ACTION" in
    on|ON|On)
        activate_lscache
        ;;
    off|OFF|Off)
        deactivate_lscache
        ;;
    *)
        echo "❌ Action non reconnue: $ACTION"
        echo "Utilisez 'on' pour activer ou 'off' pour désactiver"
        exit 1
        ;;
esac

exit 0
