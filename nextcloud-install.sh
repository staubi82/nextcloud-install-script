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

# Basis-Pakete installieren
echo -e "${YELLOW}Installiere Basis-Pakete...${NC}"
apt install -y curl wget unzip apt-transport-https lsb-release ca-certificates software-properties-common gnupg2

# Installiere PHP und benötigte Module
echo -e "${YELLOW}Installiere PHP und benötigte Module...${NC}"

# Füge PHP-Repository hinzu für aktuellste PHP-Version
echo -e "${YELLOW}Füge PHP-Repository hinzu...${NC}"
apt install -y apt-transport-https lsb-release ca-certificates 
curl -sSL https://packages.sury.org/php/README.txt | bash -

apt update

# Finde die neueste verfügbare PHP-Version
PHP_VERSION=$(apt-cache search php | grep -o "php[0-9]\.[0-9]" | sort -r | head -n1 | tr -d 'php')

if [ -z "$PHP_VERSION" ]; then
    # Fallback, wenn PHP-Version nicht gefunden werden konnte
    PHP_VERSION="8.2"
    echo -e "${YELLOW}Konnte PHP-Version nicht ermitteln, verwende PHP ${PHP_VERSION} als Standard.${NC}"
fi

echo -e "${YELLOW}Installiere PHP ${PHP_VERSION}...${NC}"

# Installiere PHP und erforderliche Module
apt install -y php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-mysql php${PHP_VERSION}-zip php${PHP_VERSION}-curl \
    php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-gd php${PHP_VERSION}-intl php${PHP_VERSION}-imagick php${PHP_VERSION}-bz2 php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-gmp php${PHP_VERSION}-ldap php${PHP_VERSION}-imap php${PHP_VERSION}-apcu redis-server php${PHP_VERSION}-redis

# Versuche php-smbclient zu installieren, aber überspringe bei Fehler
apt install -y php${PHP_VERSION}-smbclient || echo -e "${YELLOW}php-smbclient konnte nicht installiert werden, überspringe...${NC}"

# Installiere Nginx Webserver
echo -e "${YELLOW}Installiere Nginx...${NC}"
apt install -y nginx

# Installiere MariaDB
echo -e "${YELLOW}Installiere MariaDB...${NC}"
apt install -y mariadb-server mariadb-client

# PHP für bessere Performance konfigurieren
echo -e "${YELLOW}Konfiguriere PHP für bessere Performance...${NC}"
PHP_FPM_POOL_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
PHP_INI_PATH="/etc/php/${PHP_VERSION}/fpm/php.ini"

# Überprüfe, ob die Dateien existieren, bevor sie bearbeitet werden
if [ -f "$PHP_FPM_POOL_CONF" ]; then
    # PHP-FPM konfigurieren
    sed -i 's/;env\[HOSTNAME\] = /env[HOSTNAME] = /' $PHP_FPM_POOL_CONF
    sed -i 's/;env\[PATH\] = /env[PATH] = /' $PHP_FPM_POOL_CONF
    sed -i 's/;env\[TMP\] = /env[TMP] = /' $PHP_FPM_POOL_CONF
    sed -i 's/;env\[TMPDIR\] = /env[TMPDIR] = /' $PHP_FPM_POOL_CONF
    sed -i 's/;env\[TEMP\] = /env[TEMP] = /' $PHP_FPM_POOL_CONF
else
    echo -e "${YELLOW}Warnung: PHP-FPM Konfigurationsdatei konnte nicht gefunden werden: ${PHP_FPM_POOL_CONF}${NC}"
fi

if [ -f "$PHP_INI_PATH" ]; then
    # PHP.ini optimieren
    sed -i 's/memory_limit = .*/memory_limit = 512M/' $PHP_INI_PATH
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 10G/' $PHP_INI_PATH
    sed -i 's/post_max_size = .*/post_max_size = 10G/' $PHP_INI_PATH
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' $PHP_INI_PATH
    
    # OPcache-Einstellungen
    if grep -q "opcache.enable" $PHP_INI_PATH; then
        sed -i 's/;opcache.enable=.*/opcache.enable=1/' $PHP_INI_PATH
        sed -i 's/;opcache.memory_consumption=.*/opcache.memory_consumption=128/' $PHP_INI_PATH
        sed -i 's/;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=8/' $PHP_INI_PATH
        sed -i 's/;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' $PHP_INI_PATH
        sed -i 's/;opcache.revalidate_freq=.*/opcache.revalidate_freq=1/' $PHP_INI_PATH
        sed -i 's/;opcache.save_comments=.*/opcache.save_comments=1/' $PHP_INI_PATH
    else
        # Füge OPcache-Einstellungen hinzu, wenn sie nicht vorhanden sind
        echo "opcache.enable=1" >> $PHP_INI_PATH
        echo "opcache.memory_consumption=128" >> $PHP_INI_PATH
        echo "opcache.interned_strings_buffer=8" >> $PHP_INI_PATH
        echo "opcache.max_accelerated_files=10000" >> $PHP_INI_PATH
        echo "opcache.revalidate_freq=1" >> $PHP_INI_PATH
        echo "opcache.save_comments=1" >> $PHP_INI_PATH
    fi
else
    echo -e "${YELLOW}Warnung: PHP INI-Datei konnte nicht gefunden werden: ${PHP_INI_PATH}${NC}"
fi

# Füge APCu-Konfiguration hinzu
PHP_MODS_DIR="/etc/php/${PHP_VERSION}/mods-available"
if [ -d "$PHP_MODS_DIR" ]; then
    cat > $PHP_MODS_DIR/apcu.ini << 'EOF'
extension=apcu.so
apc.enabled=1
apc.shm_size=128M
apc.ttl=7200
apc.enable_cli=1
EOF
else
    echo -e "${YELLOW}Warnung: PHP mods-available Verzeichnis konnte nicht gefunden werden: ${PHP_MODS_DIR}${NC}"
fi

# MySQL/MariaDB konfigurieren
echo -e "${YELLOW}Konfiguriere MySQL/MariaDB...${NC}"
systemctl start mariadb.service || service mysql start || echo -e "${RED}Konnte MariaDB nicht starten. Überprüfe den MySQL/MariaDB-Dienst.${NC}"

# Überprüfe, ob MySQL läuft
if ! pgrep -x "mysqld" > /dev/null; then
    echo -e "${RED}MySQL/MariaDB scheint nicht zu laufen. Versuche manuell zu starten...${NC}"
    systemctl start mysql || systemctl start mariadb || service mysql start || service mariadb start
    sleep 5
    if ! pgrep -x "mysqld" > /dev/null; then
        echo -e "${RED}MySQL/MariaDB konnte nicht gestartet werden. Installation wird abgebrochen.${NC}"
        exit 1
    fi
fi

# Zufälliges Datenbankpasswort generieren
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
ROOT_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

# MariaDB root-Passwort setzen und Datenbank erstellen
echo -e "${YELLOW}Erstelle Datenbank und Benutzer...${NC}"
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

# Falls das obige Kommando fehlschlägt, versuche es mit einer alternativen Methode
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Alternative Methode für die Datenbankkonfiguration wird verwendet...${NC}"
    # Alternativ: Verwende mariadb-Befehl, wenn verfügbar
    if command -v mariadb &> /dev/null; then
        mariadb -u root << EOF
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
    else
        echo -e "${RED}Konnte Datenbank nicht konfigurieren. Überprüfe, ob MySQL/MariaDB korrekt installiert ist.${NC}"
        exit 1
    fi
fi

# Nginx konfigurieren
echo -e "${YELLOW}Konfiguriere Nginx...${NC}"
SERVER_IP=$(hostname -I | awk '{print $1}')
NEXTCLOUD_PATH="/var/www/nextcloud"

# Erstelle Nginx-Verzeichnisse, falls diese noch nicht existieren
mkdir -p /etc/nginx/sites-available
mkdir -p /etc/nginx/sites-enabled
mkdir -p /etc/nginx/ssl

# SSL-Zertifikat erstellen
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

# Verstehe das richtige PHP-FPM-Socket-Format
PHP_FPM_SOCK=$(find /var/run/php/ -name "*.sock" | head -n 1)
if [ -n "$PHP_FPM_SOCK" ]; then
    # Aktualisiere den Socket-Pfad in der Nginx-Konfiguration
    sed -i "s|server unix:/var/run/php/php-fpm.sock;|server unix:${PHP_FPM_SOCK};|g" /etc/nginx/sites-available/nextcloud
fi

# Server-IP in der Nginx-Konfiguration ersetzen
sed -i "s|SERVER_IP|${SERVER_IP}|g" /etc/nginx/sites-available/nextcloud
sed -i "s|NEXTCLOUD_PATH|${NEXTCLOUD_PATH}|g" /etc/nginx/sites-available/nextcloud

# Aktiviere Nextcloud-Site und deaktiviere Standard-Site
ln -sf /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm -f /etc/nginx/sites-enabled/default
fi

# Überprüfe Nginx-Konfiguration
nginx -t || echo -e "${YELLOW}Warnung: Nginx-Konfigurationstest fehlgeschlagen. Die Konfiguration könnte angepasst werden müssen.${NC}"

# Nextcloud herunterladen und installieren
echo -e "${YELLOW}Lade Nextcloud herunter und installiere es...${NC}"
mkdir -p ${NEXTCLOUD_PATH}

# Versuche, Nextcloud herunterzuladen
if ! wget -q https://download.nextcloud.com/server/releases/latest.zip -O /tmp/nextcloud-latest.zip; then
    echo -e "${YELLOW}wget fehlgeschlagen, versuche curl...${NC}"
    if ! curl -s -o /tmp/nextcloud-latest.zip https://download.nextcloud.com/server/releases/latest.zip; then
        echo -e "${RED}Download fehlgeschlagen. Überprüfe deine Internetverbindung.${NC}"
        exit 1
    fi
fi

# Überprüfe, ob unzip installiert ist, und installiere es gegebenenfalls
if ! command -v unzip &> /dev/null; then
    echo -e "${YELLOW}unzip nicht gefunden, installiere...${NC}"
    apt install -y unzip
fi

# Entpacke Nextcloud
if ! unzip -q /tmp/nextcloud-latest.zip -d /tmp; then
    echo -e "${RED}Konnte Nextcloud-Archiv nicht entpacken. Überprüfe, ob die Datei korrekt heruntergeladen wurde.${NC}"
    exit 1
fi

cp -r /tmp/nextcloud/. ${NEXTCLOUD_PATH}/
chown -R www-data:www-data ${NEXTCLOUD_PATH}
rm -rf /tmp/nextcloud /tmp/nextcloud-latest.zip

# Generiere einen zufälligen Admin-Benutzer und Passwort
ADMIN_USER="ncadmin"
ADMIN_PASS=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)

# Starte die Dienste neu
echo -e "${YELLOW}Starte Dienste neu...${NC}"
systemctl restart php${PHP_VERSION}-fpm || service php${PHP_VERSION}-fpm restart || echo -e "${YELLOW}Konnte PHP-FPM nicht neu starten.${NC}"
systemctl restart nginx || service nginx restart || echo -e "${YELLOW}Konnte Nginx nicht neu starten.${NC}"
systemctl restart mariadb || service mysql restart || echo -e "${YELLOW}Konnte MariaDB nicht neu starten.${NC}"
systemctl restart redis-server || service redis-server restart || echo -e "${YELLOW}Konnte Redis nicht neu starten.${NC}"

# Warte kurz, damit die Dienste vollständig gestartet sind
sleep 5

# Installiere Nextcloud über die Kommandozeile
echo -e "${YELLOW}Konfiguriere Nextcloud...${NC}"
cd ${NEXTCLOUD_PATH}

# Verwende die vollständige PHP-Pfadangabe für OCC
PHP_PATH=$(which php)
if [ -z "$PHP_PATH" ]; then
    PHP_PATH="/usr/bin/php${PHP_VERSION}"
    if [ ! -f "$PHP_PATH" ]; then
        # Versuche, den PHP-Interpreter zu finden
        PHP_PATH=$(find /usr/bin -name "php*" | grep -v phpize | head -n 1)
        if [ -z "$PHP_PATH" ]; then
            echo -e "${RED}Konnte PHP-Interpreter nicht finden. Installation wird abgebrochen.${NC}"
            exit 1
        fi
    fi
fi

# Führe die Nextcloud-Installation aus
sudo -u www-data $PHP_PATH occ maintenance:install \
    --database "mysql" \
    --database-name "${DB_NAME}" \
    --database-user "${DB_USER}" \
    --database-pass "${DB_PASS}" \
    --admin-user "${ADMIN_USER}" \
    --admin-pass "${ADMIN_PASS}" \
    --data-dir "${NEXTCLOUD_PATH}/data"

# Bei Fehlern, überprüfe die Berechtigungen und erstelle die config.php manuell
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Warnung: OCC-Befehl fehlgeschlagen. Überprüfe die Berechtigungen und versuche es erneut.${NC}"
    chown -R www-data:www-data ${NEXTCLOUD_PATH}
    chmod -R 755 ${NEXTCLOUD_PATH}
    
    # Erstelle ein Verzeichnis für die Daten
    mkdir -p ${NEXTCLOUD_PATH}/data
    chown -R www-data:www-data ${NEXTCLOUD_PATH}/data
    
    # Manuelle config.php-Erstellung
    CONFIG_PHP="${NEXTCLOUD_PATH}/config/config.php"
    if [ ! -f "$CONFIG_PHP" ]; then
        mkdir -p ${NEXTCLOUD_PATH}/config
        cat > ${CONFIG_PHP} << EOF
<?php
\$CONFIG = array (
  'instanceid' => '$(openssl rand -hex 10)',
  'passwordsalt' => '$(openssl rand -hex 30)',
  'secret' => '$(openssl rand -hex 20)',
  'trusted_domains' => 
  array (
    0 => 'localhost',
    1 => '${SERVER_IP}',
  ),
  'datadirectory' => '${NEXTCLOUD_PATH}/data',
  'dbtype' => 'mysql',
  'version' => '',
  'overwrite.cli.url' => 'https://${SERVER_IP}',
  'dbname' => '${DB_NAME}',
  'dbhost' => 'localhost',
  'dbport' => '',
  'dbtableprefix' => 'oc_',
  'dbuser' => '${DB_USER}',
  'dbpassword' => '${DB_PASS}',
  'installed' => true,
  'default_language' => 'de',
  'default_locale' => 'de_DE',
);
EOF
        chown www-data:www-data ${CONFIG_PHP}
    fi
fi

# Konfiguriere Vertrauenswürdige Domains
sudo -u www-data $PHP_PATH occ config:system:set trusted_domains 1 --value="${SERVER_IP}" || echo -e "${YELLOW}Konnte trusted_domains nicht konfigurieren.${NC}"

# Deutsch als Standardsprache setzen
sudo -u www-data $PHP_PATH occ config:system:set default_language --value="de" || echo -e "${YELLOW}Konnte default_language nicht konfigurieren.${NC}"
sudo -u www-data $PHP_PATH occ config:system:set default_locale --value="de_DE" || echo -e "${YELLOW}Konnte default_locale nicht konfigurieren.${NC}"

# Optimiere Redis-Konfiguration, wenn Redis installiert ist
if systemctl is-active --quiet redis-server || service redis-server status > /dev/null 2>&1; then
    sudo -u www-data $PHP_PATH occ config:system:set redis host --value="localhost" || echo -e "${YELLOW}Konnte Redis-Host nicht konfigurieren.${NC}"
    sudo -u www-data $PHP_PATH occ config:system:set redis port --value="6379" || echo -e "${YELLOW}Konnte Redis-Port nicht konfigurieren.${NC}"
    sudo -u www-data $PHP_PATH occ config:system:set memcache.local --value="\OC\Memcache\APCu" || echo -e "${YELLOW}Konnte memcache.local nicht konfigurieren.${NC}"
    sudo -u www-data $PHP_PATH occ config:system:set memcache.distributed --value="\OC\Memcache\Redis" || echo -e "${YELLOW}Konnte memcache.distributed nicht konfigurieren.${NC}"
    sudo -u www-data $PHP_PATH occ config:system:set memcache.locking --value="\OC\Memcache\Redis" || echo -e "${YELLOW}Konnte memcache.locking nicht konfigurieren.${NC}"
fi

# Aktiviere HTTPS-Einstellungen
sudo -u www-data $PHP_PATH occ config:system:set overwriteprotocol --value="https" || echo -e "${YELLOW}Konnte overwriteprotocol nicht konfigurieren.${NC}"

# Konfiguriere Cron-Job
echo "*/5  *  *  *  * www-data $PHP_PATH -f ${NEXTCLOUD_PATH}/cron.php" > /etc/cron.d/nextcloud
sudo -u www-data $PHP_PATH occ background:cron || echo -e "${YELLOW}Konnte background:cron nicht konfigurieren.${NC}"

# Überprüfe, ob die Installation erfolgreich war
NC_STATUS="erfolgreich"
if [ ! -f "${NEXTCLOUD_PATH}/config/config.php" ]; then
    NC_STATUS="möglicherweise unvollständig"
    echo -e "${RED}Warnung: Nextcloud-Installation scheint unvollständig zu sein. Die config.php wurde nicht gefunden.${NC}"
    echo -e "${RED}Überprüfe die Installation manuell unter https://${SERVER_IP}${NC}"
fi

# Ausgabe der Installationsinformationen
echo -e "${GREEN}Nextcloud-Installation ${NC_STATUS}!${NC}"
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

# Füge einige Diagnoseinformationen hinzu
echo -e "${YELLOW}------------------------------------------------${NC}"
echo -e "${YELLOW}Diagnose-Informationen:${NC}"
echo -e "PHP-Version: ${PHP_VERSION}"
echo -e "PHP-Socket: $(find /var/run/php/ -name "*.sock" | head -n 1)"
echo -e "Webserver: $(nginx -v 2>&1 || echo 'Nginx nicht gefunden')"
echo -e "Datenbank: $(mariadb --version 2>&1 || mysql --version 2>&1 || echo 'MySQL/MariaDB nicht gefunden')"
echo -e "${YELLOW}------------------------------------------------${NC}"

# Vorschläge zur manuellen Überprüfung
echo -e "${YELLOW}Wenn Probleme auftreten, überprüfen Sie folgende Dienste:${NC}"
echo -e "1. Nginx-Status: ${GREEN}systemctl status nginx${NC}"
echo -e "2. PHP-FPM-Status: ${GREEN}systemctl status php${PHP_VERSION}-fpm${NC}"
echo -e "3. MariaDB-Status: ${GREEN}systemctl status mariadb${NC}"
echo -e "4. Redis-Status: ${GREEN}systemctl status redis-server${NC}"
echo -e "5. Nextcloud-Log: ${GREEN}tail -f ${NEXTCLOUD_PATH}/data/nextcloud.log${NC}"
