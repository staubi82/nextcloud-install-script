#!/bin/bash

# Paketquellen aktualisieren und Systemupgrade durchführen
apt update && apt upgrade -y

# Benötigte Pakete installieren
apt install -y nginx mariadb-server php-fpm \
php-gd php-mysql php-curl php-intl php-mbstring php-xml php-zip php-bz2 php-json php-common php-cli php-opcache php-readline php-ldap wget unzip

# MariaDB konfigurieren und starten
service mysql start
mysql_secure_installation <<EOF

y
secret
secret
y
y
y
y
EOF

# Datenbank und Benutzer für Nextcloud erstellen
mysql -u root -psecret <<EOF
CREATE DATABASE nextcloud;
CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY 'secret';
GRANT ALL PRIVILEGES ON nextcloud.* TO 'nextcloud'@'localhost';
FLUSH PRIVILEGES;
EOF

# Nextcloud herunterladen und entpacken
cd /var/www
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
chown -R www-data:www-data nextcloud
chmod -R 755 nextcloud

# Nginx-Konfiguration für Nextcloud
cat > /etc/nginx/sites-available/nextcloud <<EOF
server {
    listen 80;
    server_name _;

    root /var/www/nextcloud;
    index index.php index.html /index.php\$request_uri;

    client_max_body_size 512M;
    fastcgi_buffers 64 4K;

    gzip off;

    error_page 403 /core/templates/403.php;
    error_page 404 /core/templates/404.php;

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)/ {
        deny all;
    }

    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) {
        deny all;
    }

    location / {
        rewrite ^ /index.php\$request_uri;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_split_path_info ^(.+\.php)(/.*)\$;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_pass unix:/var/run/php/php8.0-fpm.sock;
        include fastcgi_params;
    }

    location ~* \.(?:css|js|woff|svg|gif)\$ {
        try_files \$uri /index.php\$request_uri;
        add_header Cache-Control "public, max-age=15778463";
        access_log off;
    }

    location ~* \.(?:png|html|ttf|ico|jpg|jpeg)\$ {
        try_files \$uri /index.php\$request_uri;
        access_log off;
    }
}
EOF

# Nginx aktivieren und neu starten
ln -s /etc/nginx/sites-available/nextcloud /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default
systemctl restart nginx

# PHP-FPM konfigurieren
sed -i 's/;date.timezone =/date.timezone = Europe\/Berlin/' /etc/php/8.2/fpm/php.ini
systemctl restart php8.2-fpm

# Hinweis zur Erreichbarkeit von Nextcloud anzeigen
IP=$(hostname -I | awk '{print $1}')
echo -e "\n\n##############################################"
echo "Installation abgeschlossen. Du kannst jetzt auf die Nextcloud-Web-Oberfläche zugreifen:"
echo "http://$IP"
echo "##############################################\n\n"
