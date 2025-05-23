# Vérifier le montage de l'EFS

```
ubuntu@ip-10-0-101-97:~$ df -h
Filesystem                                          Size  Used Avail Use% Mounted on
/dev/root                                            20G  5.4G   14G  28% /
tmpfs                                               959M  148K  959M   1% /dev/shm
tmpfs                                               384M  892K  383M   1% /run
tmpfs                                               5.0M     0  5.0M   0% /run/lock
efivarfs                                            128K  3.8K  120K   4% /sys/firmware/efi/efivars
/dev/nvme0n1p15                                     105M  6.1M   99M   6% /boot/efi
fs-08bb4e701bb292e38.efs.us-west-2.amazonaws.com:/  8.0E     0  8.0E   0% /mnt/efs
tmpfs                                               192M  4.0K  192M   1% /run/user/1000
```

# Vérifier la création des liens symboliques vers l'EFS

```
ubuntu@ip-10-0-101-97:~$ ls -la /var/www
```

```
lrwxrwxrwx 1 root root 19 Mar 31 11:50 /var/www -> /mnt/efs/olsefs/www
```

```
ubuntu@ip-10-0-101-97:~$ ls -la /usr/local/lsws/conf
```

```
lrwxrwxrwx 1 root root 20 Mar 31 11:50 /usr/local/lsws/conf -> /mnt/efs/olsefs/conf
```

# Accéder à la console WebAdmin via le Load Balancer 

Pour cela, il faut désactiver SSL via 

WebAdmin Settings > Listeners adminListener > View 
Secure = No


# Durée exécution


```
kaiac build
```

```
End of the Composition build.
1) MODULE bkclustsg APPLY DURATION : 1m:8s
2) MODULE bkclustalb APPLY DURATION : 4m:0s
3) MODULE bkclusttg APPLY DURATION : 1m:6s
4) MODULE bkclusttg APPLY DURATION : 47s
5) MODULE bkclustlisten APPLY DURATION : 1m:0s
6) MODULE bkclustsg APPLY DURATION : 1m:21s
7) MODULE bkec2profile APPLY DURATION : 1m:8s
8) MODULE bkkeypair APPLY DURATION : 1m:6s
9) MODULE bkclustasg APPLY DURATION : 1m:22s
10) MODULE bkclustasgattach APPLY DURATION : 1m:5s
11) MODULE bkclustasgattach APPLY DURATION : 47s
12) MODULE bkr53exposer APPLY DURATION : 1m:35s
13) MODULE bkr53exposer APPLY DURATION : 1m:29s
TOTAL BUILD DURATION : 18m:51s
```

```
kaiac demolish
```

```
End of the Composition demolition.

14) MODULE bkr53exposer DESTROY DURATION : 1m:45s
13) MODULE bkr53exposer DESTROY DURATION : 1m:39s
12) MODULE bkr53exposer DESTROY DURATION : 1m:45s
11) MODULE bkclustasgattach DESTROY DURATION : 1m:18s
10) MODULE bkclustasgattach DESTROY DURATION : 57s
9) MODULE bkclustasg DESTROY DURATION : 3m:45s
8) MODULE bkkeypair DESTROY DURATION : 1m:11s
7) MODULE bkec2profile DESTROY DURATION : 1m:12s
6) MODULE bkclustsg DESTROY DURATION : 1m:19s
5) MODULE bkclustlisten DESTROY DURATION : 1m:9s
4) MODULE bkclusttg DESTROY DURATION : 1m:16s
3) MODULE bkclusttg DESTROY DURATION : 59s
2) MODULE bkclustalb DESTROY DURATION : 1m:11s
1) MODULE bkclustsg DESTROY DURATION : 1m:20s
TOTAL DEMOLITION DURATION : 21m:47s
```


# Téléchargement des scripts sh

curl -o delete_wordpress.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/wordpress_ols_ansible_https/delete_wordpress.sh


curl -o deploy_wordpress.sh https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/wordpress_ols_ansible_https/deploy_wordpress.sh

# Test la fonction Lambda

{
  "Records": [
    {
      "messageId": "19dd0b57-b21e-4ac1-bd88-01bbb068cb78",
      "receiptHandle": "MessageReceiptHandle",
      "body": "{\"command\":\"CREATE_WP\",\"domain\":\"site1.kaiac.io\",\"domain_folder\":\"site1_kaiac_io\",\"wp_db_name\":\"site1_kaiac_io_db\",\"wp_db_user\":\"wp_user\",\"wp_db_password\":\"=Dorine11\",\"php_version\":\"lsphp81\",\"wp_version\":\"6.5.2\"}",
      "attributes": {
        "ApproximateReceiveCount": "1",
        "SentTimestamp": "1523232000000",
        "SenderId": "123456789012",
        "ApproximateFirstReceiveTimestamp": "1523232000001"
        },
      "messageAttributes": {},
      "md5OfBody": "{{{md5_of_body}}}",
      "eventSource": "aws:sqs",
      "eventSourceARN": "arn:aws:sqs:us-west-2:041292242005:wordpress-site-queue.fifo",
      "awsRegion": "us-west-2"

    }
  ]
}

# Logs d'execution du script shell déclenché par Lambda

=== Configuration du déploiement WordPress ===
Domaine: site2.skyscaledev.com
Dossier: /var/www/site2_skyscaledev_com
Version WordPress: 6.5.2
Base de données: site2_skyscaledev_com_db
Utilisateur DB: site2_skyscaledev_com_db_usr
Hôte MySQL: dbols.skyscaledev.com
Version PHP: lsphp81
============================================
Installation des dépendances...
Création du dossier du site...
Le dossier existe mais n'est pas un dépôt Git.
Suppression du contenu existant et nouveau clonage...
Génération des clés de sécurité...
Configuration de wp-config.php...
Configuration de la base de données MySQL...
Configuration d'OpenLiteSpeed...
Configuration du virtual host...
Ajout du virtualhost...
Ajout de la règle map...
Redémarrage du service OpenLiteSpeed...
{
    "ChangeInfo": {
        "Id": "/change/C01837583LWI48037P9LR",
        "Status": "PENDING",
        "SubmittedAt": "2025-04-25T17:43:12.008000+00:00",
        "Comment": "Création de l'enregistrement site2.skyscaledev.com"
    }
}
Enregistrement DNS site2.site2.skyscaledev.com créé/modifié pour pointer vers ols-alb-prod-lb-182125202.us-west-2.elb.amazonaws.com
=== Déploiement terminé avec succès ===
URL: http://site2.skyscaledev.com
Methode: git
Répertoire WordPress: /var/www/site2_skyscaledev_com
Base de données: site2_skyscaledev_com_db
======================================
