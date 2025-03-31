#!/bin/bash

THE_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "Build started on $THE_DATE"

SITE_ENV=$1

ansible-playbook -i 'ec2ols.skyscaledev.com,' add_wordpress_site.yml -e "@$SITE_ENV" --private-key /root/.ssh/id_rsa -u ubuntu -v