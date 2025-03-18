#!/bin/bash

# Nextcloud Installationsscript für Debian/Ubuntu
# Dieses Script installiert Nextcloud mit Nginx, MariaDB und PHP
# Es konfiguriert die Installation mit deutschem Locale

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Als Root ausführen
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}Dieses Script muss als Root ausgeführt werden.${NC}" 1>&2
   exit 1
fi

# Systemupdate
echo -e "${YELLOW}Führe System-Update durch...${NC}"
apt update && apt upgrade -y

# Benötigte Pakete installieren
echo -e "${YELLOW}Installiere erforderliche Pakete...${NC}"
apt install -y nginx mariadb-server php-fpm php-cli php-mysql php-zip php-curl \
    php-mbstring php-xml php-gd php-intl php-imagick php-bz2 php-bcmath \
    php-gmp unzip wget ssl-cert php-apcu redis-server php-redis cron \
    php-ldap php-imap php-smbclient php-pgsql

# PHP für bessere Performance konfigurieren
echo -e "${YELLOW}Konfiguriere PHP für bessere Performance...${NC}"
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_FPM_POOL_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
PHP_INI_PATH="/etc/php/${PHP_VERSION}/fpm/php.ini"

# PHP-FPM konfigurieren
sed -i 's/;env\[HOSTNAME\] = /env[HOSTNAME] = /' $PHP_FPM_POOL_CONF
sed -i 's/;env\[PATH\] = /env[PATH] = /' $PHP_FPM_POOL_CONF
sed -i 's/;env\[TMP\] = /env[TMP] = /' $PHP_FPM_POOL_CONF
sed -i 's/;env\[TMPDIR\] = /env[TMPDIR] = /' $PHP_FPM_POOL_CONF
sed -i 's/;env\[TEMP\] = /env[TEMP] = /' $PHP_FPM_POOL_CONF

# PHP.ini optimieren
sed -i 's/memory_limit = .*/memory_limit = 512M/' $PHP_INI_PATH
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 10G/' $PHP_INI_PATH
sed -i 's/post_max_size = .*/post_max_size = 10G/' $PHP_INI_PATH
sed -i 's/max_execution_time = .*/max_execution_time = 300/' $PHP_INI_PATH
sed -i 's/;opcache.enable=.*/opcache.enable=1/' $PHP_INI_PATH
sed -i 's/;opcache.memory_consumption=.*/opcache.memory_consumption=128/' $PHP_INI_PATH
sed -i 's/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=8/' $PHP_INI_PATH
sed -i 's/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' $PHP_INI_PATH
sed -i 's/;opcache.revalidate_freq=.*/opcache.revalidate_freq=1/' $PHP_INI_PATH
sed -i 's/;opcache.save_comments=.*/opcache.save_comments=1/' $PHP_INI_PATH

# Füge APCu-Konfiguration hinzu
cat > /etc/php/${PHP_VERSION}/mods-available/apcu.ini << 'EOF'
extension=apcu.so
apc.enabled=1
apc.shm_size=128M
apc.ttl=7200
apc.enable_cli=1
EOF

# MySQL/MariaDB konfigurieren
echo -e "${YELLOW}Konfiguriere MySQL/MariaDB...${NC}"
service mariadb start

# Zufälliges Datenbankpasswort generieren
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
ROOT_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

# MariaDB root-Passwort setzen und Datenbank erstellen
mysql -u root << EOF
UPDATE mysql.user SET Password=PASSWORD('${ROOT_PASS}') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# Nginx konfigurieren
echo -e "${YELLOW}Konfiguriere Nginx...${NC}"
SERVER_IP=$(hostname -I | awk '{print $1}')
NEXTCLOUD_PATH="/var/www/nextcloud"

# SSL-Zertifikat erstellen
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/nextcloud.key -out /etc/nginx/ssl/nextcloud.crt -subj "/CN=${SERVER_IP}"

# Nginx-Konfiguration erstellen
cat > /etc/nginx/sites-available/nextcloud << 'EOF'
upstream php-handler {
    server unix:/var/run/php/php-fpm.sock;
}

server {
    listen 80;
    listen [::]:80;
    server_name SERVER_IP;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name SERVER_IP;

    ssl_certificate /etc/nginx/ssl/nextcloud.crt;
    ssl_certificate_key /etc/nginx/ssl/nextcloud.key;

    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;

    root NEXTCLOUD_PATH;

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location = /.well-known/carddav {
        return 301 $scheme://$host:$server_port/remote.php/dav;
    }
    location = /.well-known/caldav {
        return 301 $scheme://$host:$server_port/remote.php/dav;
    }

    # set max upload size
    client_max_body_size 10G;
    fastcgi_buffers 64 4K;

    # Enable gzip but do not remove ETag headers
    gzip on;
    gzip_vary on;
    gzip_comp_level 4;
    gzip_min_length 256;
    gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
    gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

    # Pagespeed is not supported by Nextcloud, so if your server is built
    # with the `ngx_pagespeed` module, uncomment this line to disable it.
    #pagespeed off;

    location / {
        rewrite ^ /index.php;
    }

    location ~ ^\/(?:build|tests|config|lib|3rdparty|templates|data)\/ {
        deny all;
    }
    location ~ ^\/(?:\.|autotest|occ|issue|indie|db_|console) {
        deny all;
    }

    location ~ ^\/(?:index|remote|public|cron|core\/ajax\/update|status|ocs\/v[12]|updater\/.+|oc[ms]-provider\/.+)\.php(?:$|\/) {
        fastcgi_split_path_info ^(.+?\.php)(\/.*|)$;
        set $path_info $fastcgi_path_info;
        try_files $fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $path_info;
        fastcgi_param HTTPS on;
        # Avoid sending the security headers twice
        fastcgi_param modHeadersAvailable true;
        # Enable pretty urls
        fastcgi_param front_controller_active true;
        fastcgi_pass php-handler;
        fastcgi_intercept_errors on;
        fastcgi_request_buffering off;
    }

    location ~ ^\/(?:updater|oc[ms]-provider)(?:$|\/) {
        try_files $uri/ =404;
        index index.php;
    }

    # Adding the cache control header for js and css files
    # Make sure it is BELOW the PHP block
    location ~ \.(?:css|js|woff2?|svg|gif|map)$ {
        try_files $uri /index.php$request_uri;
        add_header Cache-Control "public, max-age=15778463";
        # Add headers to serve security related headers
        add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "no-referrer" always;
        access_log off;
    }

    location ~ \.(?:png|html|ttf|ico|jpg|jpeg|bcmap|mp4|webm)$ {
        try_files $uri /index.php$request_uri;
        # Optional: Don't log access to other assets
        access_log off;
    }
}
EOF

# Server-IP in der Nginx-Konfiguration ersetzen
sed -i "s|SERVER_IP|${SERVER_IP}|g" /etc/nginx/sites-available/nextcloud
sed -i "s|NEXTCLOUD_PATH|${NEXTCLOUD_PATH}|g" /etc/nginx/sites-available/nextcloud

# Aktiviere Nextcloud-Site und deaktiviere Standard-Site
ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Überprüfe Nginx-Konfiguration
nginx -t

# Nextcloud herunterladen und installieren
echo -e "${YELLOW}Lade Nextcloud herunter und installiere es...${NC}"
mkdir -p ${NEXTCLOUD_PATH}
wget -q https://download.nextcloud.com/server/releases/latest.zip -O /tmp/nextcloud-latest.zip
unzip -q /tmp/nextcloud-latest.zip -d /tmp
cp -r /tmp/nextcloud/. ${NEXTCLOUD_PATH}/
chown -R www-data:www-data ${NEXTCLOUD_PATH}
rm -rf /tmp/nextcloud /tmp/nextcloud-latest.zip

# Generiere einen zufälligen Admin-Benutzer und Passwort
ADMIN_USER="ncadmin"
ADMIN_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)

# Starte die Dienste neu
echo -e "${YELLOW}Starte Dienste neu...${NC}"
systemctl restart php${PHP_VERSION}-fpm
systemctl restart nginx
systemctl restart mariadb
systemctl restart redis-server

# Warte kurz, damit die Dienste vollständig gestartet sind
sleep 5

# Installiere Nextcloud über die Kommandozeile
cd ${NEXTCLOUD_PATH}
sudo -u www-data php occ maintenance:install \
    --database "mysql" \
    --database-name "${DB_NAME}" \
    --database-user "${DB_USER}" \
    --database-pass "${DB_PASS}" \
    --admin-user "${ADMIN_USER}" \
    --admin-pass "${ADMIN_PASS}" \
    --data-dir "${NEXTCLOUD_PATH}/data"

# Konfiguriere Vertrauenswürdige Domains
sudo -u www-data php occ config:system:set trusted_domains 1 --value="${SERVER_IP}"

# Deutsch als Standardsprache setzen
sudo -u www-data php occ config:system:set default_language --value="de"
sudo -u www-data php occ config:system:set default_locale --value="de_DE"

# Optimiere Redis-Konfiguration
sudo -u www-data php occ config:system:set redis host --value="localhost"
sudo -u www-data php occ config:system:set redis port --value="6379"
sudo -u www-data php occ config:system:set memcache.local --value="\OC\Memcache\APCu"
sudo -u www-data php occ config:system:set memcache.distributed --value="\OC\Memcache\Redis"
sudo -u www-data php occ config:system:set memcache.locking --value="\OC\Memcache\Redis"

# Aktiviere HTTPS-Einstellungen
sudo -u www-data php occ config:system:set overwriteprotocol --value="https"

# Konfiguriere Cron-Job
echo "*/5  *  *  *  * www-data php -f ${NEXTCLOUD_PATH}/cron.php" > /etc/cron.d/nextcloud
sudo -u www-data php occ background:cron

# Ausgabe der Installationsinformationen
echo -e "${GREEN}Nextcloud wurde erfolgreich installiert!${NC}"
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}Nextcloud-URL:${NC} https://${SERVER_IP}"
echo -e "${YELLOW}Admin-Benutzer:${NC} ${ADMIN_USER}"
echo -e "${YELLOW}Admin-Passwort:${NC} ${ADMIN_PASS}"
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}Datenbank-Name:${NC} ${DB_NAME}"
echo -e "${YELLOW}Datenbank-Benutzer:${NC} ${DB_USER}"
echo -e "${YELLOW}Datenbank-Passwort:${NC} ${DB_PASS}"
echo -e "${YELLOW}MySQL Root-Passwort:${NC} ${ROOT_PASS}"
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${GREEN}Bitte speichern Sie diese Informationen an einem sicheren Ort!${NC}"
echo -e "${GREEN}Für mehr Sicherheit sollten Sie ein richtiges SSL-Zertifikat einrichten.${NC}"
