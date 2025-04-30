#!/bin/bash
# Script de désinstallation complète de ProFTPD
set -e

echo "=== DÉSINSTALLATION DE PROFTPD ==="

# 1. Arrêt du service
sudo systemctl stop proftpd 2>/dev/null || echo "ProFTPD n'est pas en cours d'exécution"

# 2. Désinstallation des paquets
sudo apt-get remove --purge -y \
    proftpd-basic \
    proftpd-mod-crypto \
    proftpd-doc \
    proftpd-mod-sql \
    proftpd-mod-sftp

# 3. Suppression des fichiers résiduels
sudo rm -rf \
    /etc/proftpd \
    /var/log/proftpd \
    /usr/lib/proftpd \
    /usr/share/proftpd \
    /etc/default/proftpd \
    /etc/init.d/proftpd

# 4. Nettoyage des dépendances
sudo apt-get autoremove -y

# 5. Suppression des règles firewall associées
sudo ufw delete allow 31001/tcp 2>/dev/null || true
sudo ufw delete allow 32002/tcp 2>/dev/null || true

echo "=== DÉSINSTALLATION TERMINÉE ==="
echo "ProFTPD a été complètement supprimé de votre système"