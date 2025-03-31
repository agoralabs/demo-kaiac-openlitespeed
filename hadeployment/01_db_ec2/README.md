# Se connecter à la base de données

D'abord se connecter en SSH à l'instance EC2 contenant la base de données

```
ssh -i "/root/.ssh/id_rsa" ubuntu@dbols.skyscaledev.com
```

Se connecter ensuite à la base de données

```
mysql -u root -p
```
# Vérifier le mode d’authentification du root

```
MariaDB [(none)]> SELECT user, plugin, host FROM mysql.user;
```

```
+-------------+-----------------------+-----------+
| User        | plugin                | Host      |
+-------------+-----------------------+-----------+
| mariadb.sys | mysql_native_password | localhost |
| root        | mysql_native_password | localhost |
| mysql       | mysql_native_password | localhost |
+-------------+-----------------------+-----------+
3 rows in set (0.010 sec)
```

Ici on remarque qu'il est impossible d'utiliser le root depuis une machine distante.
Pour y remedier il faut procéder comme décrit dans la section qui suit.

# Autoriser root à se connecter à distance

## Modifier les droits de l'utilisateur root

```
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '=Dorine11' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

Tu devrais avoir ceci comme affichage :

```
MariaDB [(none)]> SELECT user, plugin, host FROM mysql.user;
```

```
+-------------+-----------------------+-----------+
| User        | plugin                | Host      |
+-------------+-----------------------+-----------+
| mariadb.sys | mysql_native_password | localhost |
| root        | mysql_native_password | localhost |
| mysql       | mysql_native_password | localhost |
| root        | mysql_native_password | %         |
+-------------+-----------------------+-----------+
4 rows in set (0.001 sec)
```

## Modifier le fichier de configuration MariaDB pour accepter les connexions externes

Édite le fichier :

```
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf
```

Trouve cette ligne :

> bind-address = 127.0.0.1 

Et modifie-la en :

> bind-address = 0.0.0.0


## Redémarrer MariaDB

```
sudo systemctl restart mariadb
```

# Durées de construction/destruction de l'infrastrcuture avec KaiaC

```
kaiac build
```

```
End of the Composition build.

1) MODULE bkclustsg APPLY DURATION : 50s
2) MODULE bkec2profile APPLY DURATION : 48s
3) MODULE bkkeypair APPLY DURATION : 57s
4) MODULE bkclustec2 APPLY DURATION : 1m:24s
5) MODULE bkr53exposer APPLY DURATION : 1m:27s
TOTAL BUILD DURATION : 5m:46s
```

```
kaiac demolish
```

```
End of the Composition demolition.

5) MODULE bkr53exposer DESTROY DURATION : 1m:46s
4) MODULE bkclustec2 DESTROY DURATION : 2m:15s
3) MODULE bkkeypair DESTROY DURATION : 1m:12s
2) MODULE bkec2profile DESTROY DURATION : 1m:8s
1) MODULE bkclustsg DESTROY DURATION : 1m:20s
TOTAL DEMOLITION DURATION : 8m:1s
```
