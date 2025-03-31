# demo-kaiac-openlitespeed
Demo deploiement wordpress sur openlitespeed avec kaiac

ansible-playbook -i inventory install_openlitespeed_with_mysql.yml

# Recherche d'une image initiale

aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-2025*" \
  --query "Images[*].[ImageId,Name,CreationDate]" \
  --output table

ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20250219

-------------------------------------------------------------------------------------------------------------------------
|                                                    DescribeImages                                                     |
+-----------------------+------------------------------------------------------------------+----------------------------+
|  ami-0181d6b00c4160daf|  ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20250219  |  2025-02-19T04:13:37.000Z  |
|  ami-03888a8e79ae9d4f1|  ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20250225  |  2025-02-25T04:04:51.000Z  |
|  ami-01d1ba4beaae93566|  ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20250228  |  2025-02-28T03:28:52.000Z  |
|  ami-03f8acd418785369b|  ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20250305  |  2025-03-05T03:14:24.000Z  |
|  ami-08946671b9b9c656e|  ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20250211  |  2025-02-11T13:29:24.000Z  |
|  ami-0606dd43116f5ed57|  ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20250112  |  2025-01-12T04:14:24.000Z  |
|  ami-06d9e8c7bf793c508|  ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20250108  |  2025-01-08T17:04:07.000Z  |
+-----------------------+------------------------------------------------------------------+----------------------------+

# Installation des packages pour préparer l'AMI (Amazon Machine Image)

ansible-playbook -i '54.201.31.177,' /vagrant/demo-kaiac-openlitespeed/kvbooks/00_buildami_openlitespeed.yml --private-key /root/.ssh/id_rsa -u ubuntu

# Initialisation du compte admin OpenLiteSpeed

sudo /usr/local/lsws/admin/misc/admpass.sh

admin/********

# Initialisation du compte root de la BDD MySQL

sudo mysql

ALTER USER 'root'@'localhost' IDENTIFIED BY 'TonNouveauMotDePasseFort!';
FLUSH PRIVILEGES;

mysql -u root -p

# Étapes pour autoriser root à se connecter à distance

mysql -u root -p

GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '=Dorine11' WITH GRANT OPTION;
FLUSH PRIVILEGES;


sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf


bind-address = 127.0.0.1 ==> bind-address = 0.0.0.0


sudo systemctl restart mariadb


# Déploiement d'un site Wordpress

./add_wordpress_site.sh site.env


# Déploiement avec un système de fichiers partagés EFS


ubuntu@ip-172-31-39-165:~$ ls -la /usr/local/lsws/conf
lrwxrwxrwx 1 root root 20 Mar 28 11:59 /usr/local/lsws/conf -> /mnt/efs/olsefs/conf

ubuntu@ip-172-31-39-165:~$ ls -la /var/www
lrwxrwxrwx 1 root root 19 Mar 28 11:59 /var/www -> /mnt/efs/olsefs/www