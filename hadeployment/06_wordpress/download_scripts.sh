#!/bin/bash


# Tableaux contenant les noms des scripts à télécharger
scripts_wp=(
    "backup_wordpress.sh"
    "configure_openlitespeed.sh"
    "configure_wp_config.sh"
    "create_dns_record.sh"
    "create_mysql_database.sh"
    "delete_wordpress.sh"
    "disable_wp_ls_cache.sh"
    "install_wp_cli.sh"
    "install_wp_ls_cache.sh"
    "manage_wordpress.sh"
    "toggle_wp_lscache.sh"
    "toggle_wp_maintenance.sh"
    "update_ols_rewrite_rules.sh"
    "delete_parameters_store.sh"
    "toggle_wp_debug.sh"
    "install_wp_query_monitor.sh"
    "toggle_wp_query_monitor.sh"
    "generate_wp_report.sh"
    "size_checker.sh"
    "toggle_vhost_suspension.sh"
    "update_used_storage.sh"
    "update_is_processing_site.sh"
    "generate_all_wp_reports.sh"
    )

scripts_ftp=(
    "add_sftp_user.sh"
    "remove_sftp_user.sh"
    "deploy_sftp.sh"
    "sync_sftp_users.sh"
    "sync_remove_sftp_user.sh"
    "list_sftp_users.sh"
    )

# Boucle pour télécharger chaque script
for script in "${scripts_wp[@]}"; do
    curl -o "$script" "https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/06_wordpress/$script"
    chmod +x "$script"
done

for script in "${scripts_ftp[@]}"; do
    curl -o "$script" "https://raw.githubusercontent.com/agoralabs/demo-kaiac-openlitespeed/refs/heads/main/hadeployment/05_ftp/sftp-autoscaling/$script"
    chmod +x "$script"
done

