#!/bin/bash
# Script d'installation ProFTPD avec EFS et gestion robuste des certificats
set -e

# === 1. Configuration ===
EFS_MOUNT="/mnt/efs/olsefs"
FTP_CONFIG_DIR="$EFS_MOUNT/proftpd-config"
FTP_DATA_DIR="$EFS_MOUNT/ftp-data"
TLS_CERT_DIR="/etc/proftpd/ssl"

# Ports personnalisables (évitent les conflits)
FTP_PORT=31001
SFTP_PORT=32002

# === 2. Vérification des ports ===
check_port() {
    if ss -tuln | grep -q ":$1 "; then
        echo "ERREUR : Port $1 déjà utilisé par :" >&2
        ss -tulnp | grep ":$1 "
        exit 1
    fi
}

check_port $FTP_PORT
check_port $SFTP_PORT

# === 3. Installation des paquets ===
sudo apt-get update
sudo apt-get install -y proftpd-basic proftpd-mod-crypto openssl

# === 4. Préparation des dossiers ===
sudo mkdir -p "$FTP_CONFIG_DIR" "$FTP_DATA_DIR"
sudo chmod 755 "$FTP_DATA_DIR"

# === 5. Configuration ProFTPD ===
cat << EOF | sudo tee "$FTP_CONFIG_DIR/proftpd.conf" >/dev/null
# Config ProFTPD avec ports $FTP_PORT (FTP) et $SFTP_PORT (SFTP)
ServerName "MonServeurFTP"
ServerType standalone
DefaultServer on
Port $FTP_PORT
UseIPv6 off

<IfModule mod_sftp.c>
    SFTPEngine on
    SFTPLog /var/log/proftpd/sftp.log
    SFTPHostKey /etc/ssh/ssh_host_rsa_key
    SFTPHostKey /etc/ssh/ssh_host_ecdsa_key
    SFTPAuthMethods password
    Port $SFTP_PORT
</IfModule>

AuthOrder mod_auth_unix.c
RequireValidShell off
DefaultRoot $FTP_DATA_DIR

<IfModule mod_tls.c>
    TLSEngine on
    TLSRequired on
    TLSProtocol TLSv1.2 TLSv1.3
    TLSRSACertificateFile $TLS_CERT_DIR/proftpd.crt
    TLSRSACertificateKeyFile $TLS_CERT_DIR/proftpd.key
</IfModule>

<Directory $FTP_DATA_DIR/*>
    AllowOverwrite on
    <Limit ALL>
        AllowAll
    </Limit>
</Directory>
EOF

# === 6. Génération des certificats (nouvelle méthode robuste) ===
sudo mkdir -p "$TLS_CERT_DIR"
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout "$TLS_CERT_DIR/proftpd.key" \
    -out "$TLS_CERT_DIR/proftpd.crt" \
    -subj "/C=FR/ST=Paris/L=Paris/O=MyCompany/CN=ftp-$(hostname)" \
    -addext "subjectAltName=DNS:$(hostname)"

sudo chmod 600 "$TLS_CERT_DIR"/*
sudo chown root:root "$TLS_CERT_DIR"/*

# === 7. Vérification des certificats ===
if ! sudo openssl x509 -noout -in "$TLS_CERT_DIR/proftpd.crt"; then
    echo "ERREUR: Échec de la génération du certificat" >&2
    exit 1
fi

# === 8. Lien symbolique ===
sudo ln -sf "$FTP_CONFIG_DIR/proftpd.conf" /etc/proftpd/proftpd.conf

# === 9. Activation des modules ===
echo -e "LoadModule mod_sftp.c\nLoadModule mod_tls.c" | sudo tee -a /etc/proftpd/modules.conf

# === 10. Création utilisateur test ===
EXAMPLE_USER="ftpuser_$(date +%s | tail -c 4)"
sudo adduser --system --group --shell /bin/false --home "$FTP_DATA_DIR/$EXAMPLE_USER" "$EXAMPLE_USER"
sudo mkdir -p "$FTP_DATA_DIR/$EXAMPLE_USER/www"
sudo chown -R "$EXAMPLE_USER:$EXAMPLE_USER" "$FTP_DATA_DIR/$EXAMPLE_USER"
echo "Mot de passe pour $EXAMPLE_USER :"
sudo passwd "$EXAMPLE_USER"

# === 11. Ouverture des ports ===
sudo ufw allow $FTP_PORT/tcp
sudo ufw allow $SFTP_PORT/tcp

# === 12. Démarrage sécurisé ===
sudo systemctl daemon-reload
sudo systemctl enable proftpd
if ! sudo systemctl restart proftpd; then
    echo "=== DÉBOGAGE ==="
    sudo journalctl -u proftpd -n 20 --no-pager
    exit 1
fi

# === 13. Vérification finale ===
echo "=== INSTALLATION RÉUSSIE ==="
echo "Port FTP/FTPS: $FTP_PORT"
echo "Port SFTP: $SFTP_PORT"
echo "Utilisateur test: $EXAMPLE_USER"
echo "Certificat TLS: $TLS_CERT_DIR/proftpd.crt"
echo "Test de connexion:"
echo "  SFTP: sftp -P $SFTP_PORT $EXAMPLE_USER@$(curl -s ifconfig.me)"
echo "  FTPS: lftp -u $EXAMPLE_USER -p $FTP_PORT ftps://$(curl -s ifconfig.me)"