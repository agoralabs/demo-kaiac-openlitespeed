# Déploiement d'un site Wordpress

```
cd /vagrant/demo-kaiac-openlitespeed/wordpress_ols_ansible_https/

./add_wordpress_site.sh 001_site_vars.yml
```


mysqldump -h dbols.skyscaledev.com \
    -u root \
    -p=Dorine11 \
    --port=3306 \
    --single-transaction \
    --routines \
    --triggers \
    --databases  site1_skyscaledev_com_db > ./site1_skyscaledev_com_db-dump.sql