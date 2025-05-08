#!/bin/bash
# Script pour activer/désactiver les logs de débogage WordPress
# Usage: ./toggle_wp_debug.sh [on|off] [site_name]
# Exemple: ./toggle_wp_debug.sh on site1_skyscaledev_com

# ===== Vérifications =====
if [ "$#" -ne 2 ]; then
    echo "❌ Usage: $0 [on|off] [site_name]"
    echo "Exemple: $0 on site1_skyscaledev_com"
    exit 1
fi

ACTION="$1"
SITE_NAME="$2"
WEB_ROOT="/var/www/$SITE_NAME"

# ===== Configuration =====
LOG_DIR="/usr/local/lsws/logs/vhosts/${SITE_NAME}"  # Dossier centralisé pour les logs
DEFAULT_USER="www-data"       # Utilisateur du serveur (adaptez si nécessaire)

# Vérifier le répertoire du site
if [ ! -d "$WEB_ROOT" ]; then
    echo "❌ Le répertoire $WEB_ROOT n'existe pas."
    exit 1
fi

# Vérifier que c'est un site WordPress
if [ ! -f "${WEB_ROOT}/wp-config.php" ]; then
    echo "❌ wp-config.php introuvable dans $WEB_ROOT"
    exit 1
fi

# ===== Fonctions =====
activate_debug() {
    echo "=== Activation du mode debug pour $SITE_NAME ==="
    
    # Créer le dossier de logs et définir les permissions
    mkdir -p "$LOG_DIR"
    touch "$LOG_DIR/wp-debug.log"
    chown "$DEFAULT_USER":"$DEFAULT_USER" "$LOG_DIR/wp-debug.log"
    chmod 640 "$LOG_DIR/wp-debug.log"

    # Configurer wp-config.php via WP-CLI
    wp config set WP_DEBUG true --raw --path="$WEB_ROOT"
    wp config set WP_DEBUG_LOG "$LOG_DIR/wp-debug.log" --raw --path="$WEB_ROOT"
    wp config set WP_DEBUG_DISPLAY false --raw --path="$WEB_ROOT"
    
    echo "✅ Debug activé ! Logs écrits dans : $LOG_DIR/wp-debug.log"
    echo "🔍 Pour suivre les logs en direct : tail -f $LOG_DIR/wp-debug.log"
}

deactivate_debug() {
    echo "=== Désactivation du mode debug pour $SITE_NAME ==="
    
    # Désactiver les constantes dans wp-config.php
    wp config set WP_DEBUG false --raw --path="$WEB_ROOT"
    wp config set WP_DEBUG_LOG false --raw --path="$WEB_ROOT"
    wp config set WP_DEBUG_DISPLAY false --raw --path="$WEB_ROOT"
    
    # Optionnel : Supprimer le fichier de log (décommentez si besoin)
    # rm -f "$LOG_DIR/${SITE_NAME}_debug.log"
    
    echo "✅ Debug désactivé. Les logs ne seront plus écrits."
}

# ===== Exécution =====
case "$ACTION" in
    on|ON|On)
        activate_debug
        ;;
    off|OFF|Off)
        deactivate_debug
        ;;
    *)
        echo "❌ Action non reconnue : $ACTION"
        echo "Utilisez 'on' ou 'off'"
        exit 1
        ;;
esac

# ===== Vérification finale =====
echo "=== État actuel ==="
wp config get WP_DEBUG --path="$WEB_ROOT"
wp config get WP_DEBUG_LOG --path="$WEB_ROOT"
wp config get WP_DEBUG_DISPLAY --path="$WEB_ROOT"

exit 0