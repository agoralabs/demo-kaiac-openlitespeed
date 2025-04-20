# Installation CyberPanel

## Pré-requis en local

- Ansible
- clé ssh pour se connecter à votre VM
- KaiaC si vous voulez déployez une VM avec KaiaC (optionnel)


## Créer votre VM EC2

```
kaiac register /vagrant/demo-kaiac-openlitespeed/cyberpanel/01_vmonly_ubuntu_cyberpanel.cfg
```

```
kaiac plan
```

```
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

ARN = "arn:aws:ec2:us-west-2:041292242005:instance/i-0555fe007aa8dfaab"
DEPLOYMENT = "cbp-demo-staging"
NAME = "cbp-demo-staging-1"
PUBLIC_IP = "44.243.77.8"
```

## Récupérer l'IP publique de l'instance

```
...
PUBLIC_IP = "44.243.77.8"
```

## Lancer l'installation avec Ansible

```
ansible-playbook -i '44.243.77.8,' /vagrant/demo-kaiac-openlitespeed/cyberpanel/01_ansible_install_cyberpanel.yml --private-key /root/.ssh/id_rsa -u ubuntu
```

## Lancer l'installation manuellement

curl -o cyberpanel_install.sh https://cyberpanel.net/install.sh

./cyberpanel.sh --version ols --password random

admin password generated
85eTgMy3c0IEpH8p

mariadb -u root -p3KpZBZE8mhiXok -e "CREATE DATABASE cyberpanel"
mariadb -u root -p3KpZBZE8mhiXok -e "CREATE USER 'cyberpanel'@'localhost' IDENTIFIED BY '3KpZBZE8mhiXok'"
mariadb -u root -p3KpZBZE8mhiXok -e "GRANT ALL PRIVILEGES ON cyberpanel.* TO 'cyberpanel'@'localhost'"



## Valider l'installation

1. **Vérifiez les logs d'installation** :  
   ```bash
   cat /var/log/cyberpanel/installLogs.txt
   ```
2. **Relancez le playbook** avec les corrections.  
3. **Accédez à CyberPanel** :  
   - URL : `https://<IP_EC2>:8090`  
   - Identifiants : `admin` / Mot de passe défini dans le playbook.


          --mirror default \
          -p "{{ cyberpanel_admin_password }}" \
          -e "{{ cyberpanel_email }}"

./cyberpanel_install.sh --mirror default -p "VotreMotDePasseAdmin123!" -e "secobo@yahoo.com"