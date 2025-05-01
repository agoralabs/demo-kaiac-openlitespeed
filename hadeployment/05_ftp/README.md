Pour permettre à vos clients d'accéder à leur hébergement WordPress via SFTP avec leurs identifiants existants (ceux du portail), voici une solution sécurisée et efficace sur votre serveur Ubuntu EC2 :

### Solution recommandée : **SFTP Chroot avec authentification système (PAM)**
(Utilisant les comptes Unix existants)

1. **Configuration de base :**
```bash
sudo apt update
sudo apt install openssh-server
```

2. **Modifiez le fichier `/etc/ssh/sshd_config` :**
```bash
sudo nano /etc/ssh/sshd_config
```

Ajoutez/modifiez ces lignes :
```
Subsystem sftp internal-sftp
Match Group sftpusers
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication yes
```

3. **Créez un groupe pour les utilisateurs SFTP :**
```bash
sudo groupadd sftpusers
```

4. **Pour chaque client :**
```bash
# Créer l'utilisateur (remplacez 'client1' par le login du portail)
sudo useradd -m -G sftpusers -s /bin/false client1

# Définir le mot de passe (doit correspondre à celui du portail)
sudo passwd client1

# Configurer les permissions
sudo chown root:root /home/client1
sudo chmod 755 /home/client1

# Créer le dossier WordPress et donner les permissions
sudo mkdir /home/client1/www
sudo chown client1:client1 /home/client1/www
```

5. **Redémarrez SSH :**
```bash
sudo systemctl restart sshd
```

### Intégration avec WordPress :
1. **Dans votre portail**, utilisez ces mêmes identifiants pour l'authentification SFTP
2. **Infos de connexion à fournir au client :**
   - Host: votre-ip-ec2
   - Port: 22
   - Protocol: SFTP
   - Login: leur identifiant portail
   - Password: leur mot de passe portail
   - Chemin: `/www/`

### Solution alternative : **FTPS avec Pure-FTPd + MySQL**
(Si vous préférez stocker les identifiants dans une base de données)

1. Installez Pure-FTPd :
```bash
sudo apt install pure-ftpd-mysql
```
2. Configurez-le pour utiliser votre table d'utilisateurs existante

### Sécurité recommandée :
- Activez les fail2ban pour protéger contre les attaques par force brute
- Configurez un backup automatique des fichiers clients
- Utilisez Let's Encrypt pour le SSL si vous proposez aussi FTPS

Cette solution permet :
- Un accès sécurisé en SFTP
- L'isolation des clients (chroot)
- La réutilisation des identifiants existants
- Une maintenance simplifiée

Vous pourriez aussi automatiser la création des comptes via un script lorsque un nouveau client s'inscrit dans votre portail.

# Téléchargement des scripts sh

curl -o deploy_proftpd.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/deploy_proftpd.sh

curl -o create_user_proftpd.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/create_user_proftpd.sh

curl -o uninstall_proftpd.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/uninstall_proftpd.sh


curl -o deploy_sftp.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/deploy_sftp.sh

curl -o add_sftp_user.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/add_sftp_user.sh

curl -o sync_sftp_users.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/sync_sftp_users.sh

curl -o remove_sftp_user.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/remove_sftp_user.sh

# === INSTALLATION RÉUSSIE ===
Port FTP/FTPS: 31001
Port SFTP: 32002
Utilisateur test: ftpuser_293
Certificat TLS: /etc/proftpd/ssl/proftpd.crt
Test de connexion:
  SFTP: sftp -P 32002 ftpuser_293@35.88.184.231
  FTPS: lftp -u ftpuser_293 -p 31001 ftps://35.88.184.231