# Déploiement d'un site Wordpress

```
cd /vagrant/demo-kaiac-openlitespeed/wordpress_ols_ansible_https/

./add_wordpress_site.sh 001_site_vars.yml
```

# Faire un dump d'une base MySQL

```
mysqldump -h dbols.skyscaledev.com \
    -u root \
    -p=Dorine11 \
    --port=3306 \
    --single-transaction \
    --routines \
    --triggers \
    --databases  site1_skyscaledev_com_db > ./site1_skyscaledev_com_db-dump.sql
```

# Faire un zip d'un folder WordPress

```
cd /var/www/site1_skyscaledev_com
zip -r /chemin/vers/site1_skyscaledev_com.zip ./*
```

# Vérifier que le ZIP contient bien ce que vous voulez

```
unzip -l site1_skyscaledev_com.zip
```