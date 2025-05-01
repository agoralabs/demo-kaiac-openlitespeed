# Solution SFTP pour WordPress avec autoscaling

Cette solution permet de gérer des utilisateurs SFTP pour des sites WordPress hébergés sur OpenLiteSpeed dans un environnement d'autoscaling AWS. Les fichiers WordPress sont stockés sur EFS et les comptes utilisateurs sont synchronisés entre toutes les instances via AWS SSM Parameter Store.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  EC2 Instance 1 │     │  EC2 Instance 2 │     │  EC2 Instance N │
│  OpenLiteSpeed  │     │  OpenLiteSpeed  │     │  OpenLiteSpeed  │
│  SFTP Server    │     │  SFTP Server    │     │  SFTP Server    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Amazon EFS (WordPress files)               │
└─────────────────────────────────────────────────────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SSM Parameter Store                        │
│                     (Centralized user accounts)                 │
└─────────────────────────────────────────────────────────────────┘
```

## Prérequis

1. Un système de fichiers EFS monté sur toutes les instances EC2
2. Un groupe d'autoscaling avec des instances EC2 exécutant Ubuntu
3. Un rôle IAM pour les instances EC2 avec les autorisations suivantes:
   - `ssm:GetParameter`
   - `ssm:PutParameter`
   - `ssm:SendCommand`

## Installation

### 1. Préparation

1. Créez un répertoire pour les scripts:
```bash
mkdir -p /opt/sftp-autoscaling
```

2. Copiez tous les scripts de ce répertoire vers `/opt/sftp-autoscaling/` sur une instance de gestion ou via AWS Systems Manager.

3. Rendez les scripts exécutables:
```bash
chmod +x /opt/sftp-autoscaling/*.sh
```

### 2. Configuration initiale

1. Créez le paramètre SSM pour stocker les utilisateurs:
```bash
aws ssm put-parameter \
  --name "/sftp/users" \
  --type "SecureString" \
  --value "[]" \
  --description "SFTP users for WordPress sites"
```

2. Configurez le script d'initialisation pour les instances EC2:
   - Ajoutez le contenu de `ec2-user-data.sh` au user-data de votre modèle de lancement ou configuration de lancement.
   - Ou configurez-le comme script de démarrage via cloud-init.

### 3. Déploiement sur les instances existantes

Exécutez le script de déploiement sur toutes les instances existantes:
```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:AutoScalingGroupName,Values=mon-groupe-autoscaling" \
  --parameters commands="/opt/sftp-autoscaling/deploy_sftp.sh"
```

## Utilisation

### Ajouter un utilisateur SFTP

```bash
/opt/sftp-autoscaling/add_sftp_user.sh <site_name> <username> <password>
```

Exemple:
```bash
/opt/sftp-autoscaling/add_sftp_user.sh monsite client1 password123
```

### Supprimer un utilisateur SFTP

```bash
/opt/sftp-autoscaling/remove_sftp_user.sh <username>
```

Exemple:
```bash
/opt/sftp-autoscaling/remove_sftp_user.sh client1
```

### Lister tous les utilisateurs SFTP

```bash
/opt/sftp-autoscaling/list_sftp_users.sh
```

## Intégration avec le cycle de vie de l'autoscaling

Pour s'assurer que chaque nouvelle instance a les utilisateurs SFTP configurés:

1. Créez un hook de cycle de vie pour votre groupe d'autoscaling:
```bash
aws autoscaling put-lifecycle-hook \
  --lifecycle-hook-name "SyncSFTPUsers" \
  --auto-scaling-group-name "mon-groupe-autoscaling" \
  --lifecycle-transition "autoscaling:EC2_INSTANCE_LAUNCHING" \
  --heartbeat-timeout 300 \
  --default-result "CONTINUE"
```

2. Configurez une règle EventBridge pour déclencher une fonction Lambda:
```bash
aws events put-rule \
  --name "ASGLifecycleHook" \
  --event-pattern '{
    "source": ["aws.autoscaling"],
    "detail-type": ["EC2 Instance-launch Lifecycle Action"]
  }'
```

3. Utilisez la fonction Lambda fournie dans `lambda_sync_users.py` pour synchroniser les utilisateurs.

## Sécurité

- Les mots de passe sont stockés de manière sécurisée dans SSM Parameter Store en tant que SecureString
- Fail2ban est configuré pour protéger contre les attaques par force brute
- Les utilisateurs sont isolés dans leur propre environnement chroot
- Aucun accès shell n'est accordé aux utilisateurs SFTP

## Dépannage

### Vérifier l'état du service SFTP
```bash
systemctl status ssh
```

### Vérifier les journaux SFTP
```bash
tail -f /var/log/auth.log
```

### Vérifier les montages EFS
```bash
mount | grep efs
```

### Vérifier les montages bind
```bash
mount | grep bind
```

### Tester la connexion SFTP
```bash
sftp username@localhost
```

## Structure de la solution

La solution utilise AWS SSM Parameter Store pour stocker de manière centralisée les informations des utilisateurs SFTP. Voici les composants principaux:

1. Scripts de gestion des utilisateurs:
   • add_sftp_user.sh: Ajoute un utilisateur SFTP et le synchronise sur toutes les instances
   • remove_sftp_user.sh: Supprime un utilisateur SFTP de toutes les instances
   • list_sftp_users.sh: Liste tous les utilisateurs SFTP configurés

2. Scripts d'infrastructure:
   • deploy_sftp.sh: Configure le serveur SFTP sur une instance
   • sync_sftp_users.sh: Synchronise les utilisateurs depuis SSM Parameter Store
   • ec2-user-data.sh: Script à utiliser dans le user-data des instances EC2

3. Intégration avec AWS:
   • lambda_sync_users.py: Fonction Lambda pour synchroniser les utilisateurs lors du lancement d'une instance
   • iam_policy.json: Politique IAM nécessaire pour les instances EC2

## Comment utiliser cette solution

### 1. Configuration initiale

1. Créez le paramètre SSM pour stocker les utilisateurs:
bash
aws ssm put-parameter \
  --name "/sftp/users" \
  --type "SecureString" \
  --value "[]" \
  --description "SFTP users for WordPress sites"


2. Attachez la politique IAM iam_policy.json au rôle de vos instances EC2.

3. Configurez le script ec2-user-data.sh dans le user-data de votre modèle de lancement:
   • Modifiez les variables EFS_ID et EFS_REGION pour correspondre à votre configuration.

### 2. Déploiement sur les instances existantes

Exécutez le script de déploiement sur toutes les instances existantes:
bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=tag:AutoScalingGroupName,Values=mon-groupe-autoscaling" \
  --parameters commands="/opt/sftp-autoscaling/deploy_sftp.sh"


### 3. Gestion des utilisateurs

Pour ajouter un utilisateur SFTP:
bash
sudo /opt/sftp-autoscaling/add_sftp_user.sh monsite client1 password123


Pour supprimer un utilisateur SFTP:
bash
sudo /opt/sftp-autoscaling/remove_sftp_user.sh client1


Pour lister tous les utilisateurs SFTP:
bash
/opt/sftp-autoscaling/list_sftp_users.sh


## Fonctionnement

1. Lorsque vous ajoutez un utilisateur:
   • Les informations sont stockées dans SSM Parameter Store
   • Un script de synchronisation est exécuté sur toutes les instances
   • L'utilisateur est créé avec accès à son répertoire WordPress

2. Lorsqu'une nouvelle instance est lancée:
   • Le script user-data configure le serveur SFTP
   • Il synchronise tous les utilisateurs existants depuis SSM Parameter Store
   • Les utilisateurs ont immédiatement accès à leurs fichiers via EFS

3. Les fichiers WordPress sont stockés sur EFS:
   • Tous les utilisateurs accèdent aux mêmes fichiers, quelle que soit l'instance
   • Les modifications sont immédiatement visibles sur toutes les instances

Cette solution garantit que:
• Les utilisateurs sont créés une seule fois
• Les informations d'authentification sont stockées de manière sécurisée
• Toutes les instances ont accès aux mêmes utilisateurs
• Les fichiers WordPress sont partagés via EFS

# Téléchargement des scripts sh

curl -o deploy_proftpd.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/deploy_proftpd.sh

curl -o create_user_proftpd.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/create_user_proftpd.sh

curl -o uninstall_proftpd.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/uninstall_proftpd.sh


curl -o deploy_sftp.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/deploy_sftp.sh

curl -o add_sftp_user.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/add_sftp_user.sh

curl -o sync_sftp_users.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/sync_sftp_users.sh

curl -o remove_sftp_user.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/remove_sftp_user.sh

curl -o sync_remove_sftp_user.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/sync_remove_sftp_user.sh