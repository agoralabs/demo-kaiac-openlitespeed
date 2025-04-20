# Installation de Mailcow (Dockerized)

## Pré-requis
Un serveur/VPS propre (Ubuntu 20.04+ ou Debian 11+)

Nom de domaine pointant vers ton serveur (ex: mail.example.com)

Ports ouverts :

25, 80, 443, 587, 993, 995 (etc.)

UFW/iptables doit permettre le trafic mail/web

Docker + Docker Compose installés

# Préparer le système

## Mettez à jour le système
```
sudo apt update && sudo apt upgrade -y
```
## Installez Docker et Docker Compose
```
sudo apt install -y docker.io docker-compose
```
## Démarrer et activer Docker
```
sudo systemctl enable --now docker
```

# Télécharger Mailcow

## Aller dans /opt (ou un autre dossier de ton choix)
cd /opt

## Cloner le dépôt Mailcow
git clone https://github.com/mailcow/mailcow-dockerized

cd mailcow-dockerized

# Lancer l'installation

./generate_config.sh

# Mettre à jour le mot de passe admin

./helper-scripts/mailcow-reset-admin.sh

root@ip-10-0-101-91:/opt/mailcow-dockerized# ./helper-scripts/mailcow-reset-admin.sh 
Checking MySQL service... OK
Are you sure you want to reset the mailcow administrator account? [y/N] y

Working, please wait...

Reset credentials:
---
Username: admin
Password: CoOi3c0sBE85yggv
TFA: none

# Tester le bon fonctionnement

## Accéder à l’interface Mailcow
Une fois les services lancés, ouvre :

https://mail.skyscaledev.com

Identifiants par défaut :

login : admin

mot de passe : généré au 1er lancement (ou défini dans docker-compose.override.yml si tu veux le personnaliser)