#!/bin/bash

# === Configuration ===
BACKUP_DIR="/backup/glpi"         # Dossier de sauvegarde
GLPI_DIR="/var/www/glpi"     # Chemin d'installation de GLPI
DB_NAME="glpi"                    # Nom de la base de données
DB_USER="root"                    # Utilisateur MySQL/MariaDB
DB_PASS="password"                 # Mot de passe MySQL/MariaDB
RETENTION_DAYS=7                   # Nombre de jours avant suppression des anciennes sauvegardes
DATE=$(date +"%Y%m%d_%H%M%S")
GLPI_DOWNLOAD_URL="https://github.com/glpi-project/glpi/releases/latest/download/glpi.tgz"
APACHE_USER="www-data"             # Utilisateur Apache/Nginx

# === Fonction : Liste des sauvegardes ===
list_backups() {
    echo "Sauvegardes disponibles :"
    ls -1 "$BACKUP_DIR" | grep -E "glpi_files_.*.tar.gz" | sed -E "s/glpi_files_(.*).tar.gz/\1/"
}

# === Fonction : Sauvegarde GLPI ===
backup_glpi() {
    echo "🔹 Démarrage de la sauvegarde..."
    
    # Création du dossier de sauvegarde s'il n'existe pas
    mkdir -p "$BACKUP_DIR"

    # Sauvegarde des fichiers GLPI
    tar -czf "$BACKUP_DIR/glpi_files_$DATE.tar.gz" "$GLPI_DIR"

    # Sauvegarde de la base de données GLPI
    mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" | gzip > "$BACKUP_DIR/glpi_db_$DATE.sql.gz"

    # Suppression des anciennes sauvegardes
    find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

    echo "✅ Sauvegarde terminée : $BACKUP_DIR"
}

# === Fonction : Restauration GLPI ===
restore_glpi() {
    echo "🔹 Restauration d'une sauvegarde..."
    
    # Liste des sauvegardes disponibles
    list_backups

    # Demande à l'utilisateur de choisir une sauvegarde
    read -p "Entrez la date de la sauvegarde à restaurer (ex: 20240212_153000) : " CHOSEN_DATE

    # Vérification de l'existence des fichiers
    FILE_BACKUP="$BACKUP_DIR/glpi_files_$CHOSEN_DATE.tar.gz"
    DB_BACKUP="$BACKUP_DIR/glpi_db_$CHOSEN_DATE.sql.gz"

    if [[ ! -f "$FILE_BACKUP" || ! -f "$DB_BACKUP" ]]; then
        echo "❌ Erreur : La sauvegarde spécifiée n'existe pas."
        exit 1
    fi

    # Restauration des fichiers GLPI
    echo "🔄 Restauration des fichiers..."
    tar -xzf "$FILE_BACKUP" -C /

    # Restauration de la base de données
    echo "🔄 Restauration de la base de données..."
    gunzip < "$DB_BACKUP" | mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME"

    # Correction des permissions après la restauration
    fix_permissions

    echo "✅ Restauration terminée !"
}

# === Fonction : Mise à jour de GLPI ===
update_glpi() {
    echo "🔹 Recherche de la dernière version de GLPI..."

    # Récupération du lien du dernier fichier tar.gz depuis GitHub
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | grep "browser_download_url.*tgz" | cut -d '"' -f 4)

    if [[ -z "$LATEST_RELEASE" ]]; then
        echo "❌ Impossible de récupérer la dernière version. Vérifie l'accès à GitHub."
        exit 1
    fi

    echo "📥 Téléchargement de la dernière version : $LATEST_RELEASE"
    
    # Sauvegarde avant mise à jour
    backup_glpi

    # Téléchargement de l'archive
    wget -O /tmp/glpi.tgz "$LATEST_RELEASE"

    # Décompression de l’archive
    tar -xzf /tmp/glpi.tgz -C /tmp/

    echo "🔄 Mise à jour en cours..."

    # Déplacement des anciens fichiers
    mv "$GLPI_DIR" "$GLPI_DIR-old"

    # Installation de la nouvelle version
    mv /tmp/glpi "$GLPI_DIR"

    # Restauration des fichiers de configuration et données
    cp -R "$GLPI_DIR-old/config" "$GLPI_DIR/"
    cp -R "$GLPI_DIR-old/files" "$GLPI_DIR/"

    # Suppression des fichiers temporaires
    rm -rf /tmp/glpi /tmp/glpi.tgz "$GLPI_DIR-old"

    # Correction des permissions
    fix_permissions

    echo "✅ Mise à jour terminée !"
    echo "⚠️ IMPORTANT : Rendez-vous sur l'interface web de GLPI pour finaliser l'installation."
}


# === Fonction : Correction des permissions ===
fix_permissions() {
    echo "🔹 Correction des permissions sur GLPI..."
    chown -R "$APACHE_USER":"$APACHE_USER" "$GLPI_DIR"
    chmod -R 755 "$GLPI_DIR"
    chmod -R 777 "$GLPI_DIR/files" "$GLPI_DIR/config" "$GLPI_DIR/marketplace"
    echo "✅ Permissions corrigées !"
}

# === Fonction : Suppression du fichier install.php après mise à jour ===
remove_install_file() {
    INSTALL_FILE="$GLPI_DIR/install/install.php"

    if [[ -f "$INSTALL_FILE" ]]; then
        echo "🛑 Suppression du fichier d'installation pour sécuriser GLPI..."
        rm -f "$INSTALL_FILE"
        echo "✅ Fichier install.php supprimé avec succès !"
    else
        echo "ℹ️ Aucun fichier install.php trouvé, rien à supprimer."
    fi
}

# === Menu principal ===
if [[ "$1" == "backup" ]]; then
    backup_glpi
elif [[ "$1" == "restore" ]]; then
    restore_glpi
elif [[ "$1" == "update" ]]; then
    update_glpi
elif [[ "$1" == "installfile" ]]; then
    remove_install_file
elif [[ "$1" == "fix-permissions" ]]; then
    fix_permissions
else
    echo "Utilisation : $0 {backup|restore|update|installfile|fix-permissions}"
    exit 1
fi
