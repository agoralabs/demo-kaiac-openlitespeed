#!/bin/bash
# Installation ProFTPD avec EFS et ports personnalisés
set -e

# === 1. Variables à personnaliser ===
EFS_MOUNT="/mnt/efs/olsefs"               # Chemin EFS
FTP_CONFIG_DIR="$EFS_MOUNT/proftpd-config" # Config ProFTPD
FTP_DATA_DIR="$EFS_MOUNT/ftp-data"         # Dossier données
TLS_CERT_DIR="/etc/proftpd/ssl"            # Certificats TLS

# === 2. Paramètres des ports (modifiables) ===
DEFAULT_FTP_PORT=31001                    # Port FTP/FTPS
DEFAULT_SFTP_PORT=32002                   # Port SFTP

# Demander les ports si non définis en variables d'environnement
FTP_PORT=${PROFTPD_FTP_PORT:-$DEFAULT_FTP_PORT}
SFTP_PORT=${PROFTPD_SFTP_PORT:-$DEFAULT_SFTP_PORT}

# === 3. Vérification des ports disponibles ===
check_port() {
    if ss -tuln | grep -q ":$1 "; then
        echo "ERREUR : Le port $1 est déjà utilisé" >&2
        ss -tuln | grep ":$1 "
        exit 1
    fi
}

check_port $FTP_PORT
check_port $SFTP_PORT

# === 4. Installation des paquets ===
sudo apt-get update
sudo apt-get install -y proftpd-basic proftpd-mod-crypto openssl

# === 5. Préparation des dossiers ===
sudo mkdir -p "$FTP_CONFIG_DIR" "$FTP_DATA_DIR"
sudo chmod 755 "$FTP_DATA_DIR"

# === 6. Configuration ProFTPD ===
if [ ! -f "$FTP_CONFIG_DIR/proftpd.conf" ]; then
    cat << EOF | sudo tee "$FTP_CONFIG_DIR/proftpd.conf"
# Config ProFTPD avec ports personnalisés
ServerName "MonServeurFTP"
ServerType standalone
DefaultServer on
Port ${FTP_PORT}
UseIPv6 off

# Modules
Include /etc/proftpd/modules.conf

# SFTP
<IfModule mod_sftp.c>
    SFTPEngine on
    SFTPLog /var/log/proftpd/sftp.log
    SFTPHostKey /etc/ssh/ssh_host_rsa_key
    SFTPHostKey /etc/ssh/ssh_host_ecdsa_key
    SFTPAuthMethods password
    Port ${SFTP_PORT}
</IfModule>

# Authentification
AuthOrder mod_auth_unix.c
RequireValidShell off
DefaultRoot $FTP_DATA_DIR

# TLS
<IfModule mod_tls.c>
    TLSEngine on
    TLSRequired on
    TLSProtocol TLSv1.2 TLSv1.3
    TLSRSACertificateFile $TLS_CERT_DIR/proftpd.crt
    TLSRSACertificateKeyFile $TLS_CERT_DIR/proftpd.key
</IfModule>

# Permissions
<Directory $FTP_DATA_DIR/*>
    AllowOverwrite on
    <Limit ALL>
        AllowAll
    </Limit>
</Directory>
EOF

    # Certificat auto-signé
    sudo mkdir -p "$TLS_CERT_DIR"
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$TLS_CERT_DIR/proftpd.key" \
        -out "$TLS_CERT_DIR/proftpd.crt" \
        -subj "/CN=ftp-server"
    sudo chmod 600 "$TLS_CERT_DIR"/*
fi

# === 7. Lien symbolique et activation ===
sudo ln -sf "$FTP_CONFIG_DIR/proftpd.conf" /etc/proftpd/proftpd.conf
echo "LoadModule mod_sftp.c" | sudo tee -a /etc/proftpd/modules.conf
echo "LoadModule mod_tls.c" | sudo tee -a /etc/proftpd/modules.conf

# === 8. Création utilisateur exemple ===
EXAMPLE_USER="client1"
if ! id "$EXAMPLE_USER" &>/dev/null; then
    sudo adduser --disabled-password --gecos "" "$EXAMPLE_USER"
    sudo mkdir -p "$FTP_DATA_DIR/$EXAMPLE_USER"
    sudo chown "$EXAMPLE_USER:$EXAMPLE_USER" "$FTP_DATA_DIR/$EXAMPLE_USER"
    echo "Utilisateur exemple: $EXAMPLE_USER"
    echo "Pour définir un mot de passe: sudo passwd $EXAMPLE_USER"
fi

# === 9. Ouverture des ports ===
sudo ufw allow ${FTP_PORT}/tcp
sudo ufw allow ${SFTP_PORT}/tcp

# === 10. Démarrer le service ===
sudo systemctl enable proftpd
sudo systemctl restart proftpd

# === Résumé ===
echo "=== Installation terminée ==="
echo "Port FTP/FTPS: ${FTP_PORT}"
echo "Port SFTP: ${SFTP_PORT}"
echo "Config: ${FTP_CONFIG_DIR}/proftpd.conf"
echo "Test de connexion:"
echo "  SFTP: sftp -P ${SFTP_PORT} ${EXAMPLE_USER}@$(hostname -I | awk '{print $1}')"
echo "  FTPS: lftp -u ${EXAMPLE_USER} -p ${FTP_PORT} ftps://$(hostname -I | awk '{print $1}')"