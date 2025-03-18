#!/bin/bash

# MySQL/MariaDB Installations- und Reparaturscript
# Dieses Script installiert und konfiguriert MySQL/MariaDB für die Nextcloud-Installation

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

echo -e "${YELLOW}=== MySQL/MariaDB Diagnose und Reparatur ===${NC}"

# Prüfe, ob MySQL/MariaDB installiert ist
echo -e "${YELLOW}Prüfe MySQL/MariaDB Installation...${NC}"
if dpkg -l | grep -q 'mysql-server\|mariadb-server'; then
    echo -e "${GREEN}MySQL/MariaDB ist installiert.${NC}"
else
    echo -e "${YELLOW}MySQL/MariaDB ist nicht installiert. Installiere jetzt...${NC}"
    # Aktualisiere zuerst die Paketlisten
    apt update
    
    # Versuche MariaDB zu installieren
    echo -e "${YELLOW}Installiere MariaDB...${NC}"
    apt install -y mariadb-server mariadb-client
    
    # Überprüfe, ob die Installation erfolgreich war
    if ! dpkg -l | grep -q 'mariadb-server'; then
        echo -e "${YELLOW}MariaDB-Installation fehlgeschlagen. Versuche MySQL...${NC}"
        apt install -y mysql-server mysql-client
        
        # Überprüfe erneut
        if ! dpkg -l | grep -q 'mysql-server'; then
            echo -e "${RED}Konnte weder MariaDB noch MySQL installieren. Bitte überprüfe deine Paketverwaltung.${NC}"
            echo -e "${YELLOW}Führe eine manuelle Fehlersuche durch:${NC}"
            echo -e "- Überprüfe die Paketverwaltung: ${GREEN}apt update${NC}"
            echo -e "- Suche nach Paketfehlern: ${GREEN}dpkg --configure -a${NC}"
            echo -e "- Repariere Abhängigkeiten: ${GREEN}apt --fix-broken install${NC}"
            exit 1
        fi
    fi
fi

# Prüfe den Status des Dienstes
echo -e "${YELLOW}Prüfe MySQL/MariaDB Dienststatus...${NC}"

# Identifiziere den Dienst (MySQL oder MariaDB)
DB_SERVICE=""
if systemctl list-unit-files | grep -q 'mariadb.service'; then
    DB_SERVICE="mariadb"
elif systemctl list-unit-files | grep -q 'mysql.service'; then
    DB_SERVICE="mysql"
else
    echo -e "${YELLOW}Konnte den Datenbank-Dienst nicht identifizieren. Prüfe beide...${NC}"
    if [ -f /usr/sbin/mysqld ] || [ -f /usr/bin/mysqld ]; then
        echo -e "${YELLOW}MySQL binaries gefunden.${NC}"
        DB_SERVICE="mysql"
    elif [ -f /usr/sbin/mariadbd ] || [ -f /usr/bin/mariadbd ]; then
        echo -e "${YELLOW}MariaDB binaries gefunden.${NC}"
        DB_SERVICE="mariadb"
    else
        echo -e "${RED}Konnte weder MySQL noch MariaDB Dienstdateien finden.${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Identifizierter Datenbankdienst: ${DB_SERVICE}${NC}"

# Versuche, den Dienst zu stoppen, falls er bereits läuft
echo -e "${YELLOW}Stoppe bestehenden Dienst...${NC}"
systemctl stop ${DB_SERVICE} 2>/dev/null || service ${DB_SERVICE} stop 2>/dev/null
sleep 2

# Prüfe auf laufende MySQL-Prozesse und beende sie bei Bedarf
if pgrep -x "mysqld" > /dev/null || pgrep -x "mariadbd" > /dev/null; then
    echo -e "${YELLOW}Es laufen noch Datenbankprozesse. Versuche, diese zu beenden...${NC}"
    killall -9 mysqld mariadbd 2>/dev/null
    sleep 2
fi

# Überprüfe und repariere Datenbankdateien
echo -e "${YELLOW}Prüfe Datenbankdateien...${NC}"

# Finde den Datenverzeichnispfad
DATA_DIR=""
if [ -d "/var/lib/mysql" ]; then
    DATA_DIR="/var/lib/mysql"
elif [ -d "/var/lib/mariadb" ]; then
    DATA_DIR="/var/lib/mariadb"
else
    echo -e "${YELLOW}Standard-Datenverzeichnis nicht gefunden. Erstelle neues Verzeichnis...${NC}"
    mkdir -p /var/lib/mysql
    DATA_DIR="/var/lib/mysql"
fi

# Überprüfe Berechtigungen des Datenverzeichnisses
echo -e "${YELLOW}Setze Berechtigungen für das Datenverzeichnis...${NC}"
chown -R mysql:mysql ${DATA_DIR} || {
    echo -e "${YELLOW}Konnte Berechtigungen nicht setzen. Versuche mit systemctl mysql:mysql...${NC}"
    chown -R mysql:mysql ${DATA_DIR}
}

# Initialisiere die Datenbank wenn nötig
if [ ! -f "${DATA_DIR}/ibdata1" ] && [ ! -d "${DATA_DIR}/mysql" ]; then
    echo -e "${YELLOW}Keine Datenbankdateien gefunden. Initialisiere neue Datenbank...${NC}"
    
    # MySQL 5.7+/MariaDB 10.3+ Initialisierung
    if [ -x /usr/bin/mysql_install_db ]; then
        echo -e "${YELLOW}Verwende mysql_install_db...${NC}"
        mysql_install_db --user=mysql --datadir=${DATA_DIR}
    elif [ -x /usr/bin/mysqld ]; then
        echo -e "${YELLOW}Verwende mysqld --initialize-insecure...${NC}"
        mysqld --initialize-insecure --user=mysql --datadir=${DATA_DIR}
    elif [ -x /usr/bin/mariadb-install-db ]; then
        echo -e "${YELLOW}Verwende mariadb-install-db...${NC}"
        mariadb-install-db --user=mysql --datadir=${DATA_DIR}
    else
        echo -e "${RED}Konnte keine Datenbank-Initialisierungstools finden.${NC}"
        exit 1
    fi
fi

# Starte den Dienst
echo -e "${YELLOW}Starte MySQL/MariaDB Dienst...${NC}"
systemctl start ${DB_SERVICE} || service ${DB_SERVICE} start

# Warte kurz und prüfe, ob der Dienst läuft
sleep 5
if systemctl is-active --quiet ${DB_SERVICE} || service ${DB_SERVICE} status >/dev/null; then
    echo -e "${GREEN}MySQL/MariaDB Dienst läuft jetzt!${NC}"
else
    echo -e "${YELLOW}Dienst konnte nicht gestartet werden. Prüfe zusätzliche Probleme...${NC}"
    
    # Überprüfe auf häufige Fehler
    echo -e "${YELLOW}Überprüfe Fehlerprotokolle...${NC}"
    if [ -f /var/log/mysql/error.log ]; then
        echo -e "${YELLOW}Letzte 10 Zeilen des MySQL-Fehlerprotokolls:${NC}"
        tail -10 /var/log/mysql/error.log
    elif [ -f /var/log/mysql.log ]; then
        echo -e "${YELLOW}Letzte 10 Zeilen des MySQL-Fehlerprotokolls:${NC}"
        tail -10 /var/log/mysql.log
    elif [ -f /var/log/mysqld.log ]; then
        echo -e "${YELLOW}Letzte 10 Zeilen des MySQL-Fehlerprotokolls:${NC}"
        tail -10 /var/log/mysqld.log
    fi
    
    # Versuche einen manuellen Start mit Debugging
    echo -e "${YELLOW}Versuche manuellen Start mit Debugging...${NC}"
    if [ "${DB_SERVICE}" = "mysql" ]; then
        mysqld --verbose &
    else
        mariadbd --verbose &
    fi
    sleep 5
    
    # Überprüfe erneut den Status
    if pgrep -x "mysqld" > /dev/null || pgrep -x "mariadbd" > /dev/null; then
        echo -e "${GREEN}Datenbankserver läuft jetzt!${NC}"
        # Stoppe den manuell gestarteten Prozess
        if [ "${DB_SERVICE}" = "mysql" ]; then
            killall mysqld
        else
            killall mariadbd
        fi
        # Starte den Dienst normal
        systemctl start ${DB_SERVICE} || service ${DB_SERVICE} start
        sleep 2
    else
        echo -e "${RED}Konnte MySQL/MariaDB nicht starten.${NC}"
        echo -e "${YELLOW}Mögliche Lösungen:${NC}"
        echo -e "1. Überprüfe, ob der Port 3306 frei ist: ${GREEN}netstat -tulpn | grep 3306${NC}"
        echo -e "2. Versichere dich, dass genügend Speicherplatz vorhanden ist: ${GREEN}df -h${NC}"
        echo -e "3. Überprüfe die Systemprotokolle: ${GREEN}journalctl -xe${NC}"
        echo -e "4. Versuche eine Neuinstallation: ${GREEN}apt purge mysql-server mariadb-server && apt autoremove && apt install mariadb-server${NC}"
        exit 1
    fi
fi

# Erstelle einen Testbenutzer und eine Testdatenbank
echo -e "${YELLOW}Erstelle einen Testbenutzer und eine Testdatenbank...${NC}"
DB_TEST_NAME="nextcloud_test"
DB_TEST_USER="nextcloud_test"
DB_TEST_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

# Überprüfe MySQL-Zugriff
echo -e "${YELLOW}Überprüfe MySQL-Zugriff...${NC}"
if mysql -u root -e "SELECT 1" > /dev/null 2>&1; then
    echo -e "${GREEN}MySQL-Zugriff als Root ohne Passwort möglich.${NC}"
    
    mysql -u root << EOF
CREATE DATABASE IF NOT EXISTS ${DB_TEST_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_TEST_USER}'@'localhost' IDENTIFIED BY '${DB_TEST_PASS}';
GRANT ALL PRIVILEGES ON ${DB_TEST_NAME}.* TO '${DB_TEST_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
else
    echo -e "${YELLOW}Root-Zugriff erfordert möglicherweise ein Passwort oder verwendet socket-Authentifizierung.${NC}"
    
    # Versuche mit sudo
    echo -e "${YELLOW}Versuche mit sudo...${NC}"
    if sudo mysql -e "SELECT 1" > /dev/null 2>&1; then
        echo -e "${GREEN}MySQL-Zugriff mit sudo möglich.${NC}"
        
        sudo mysql << EOF
CREATE DATABASE IF NOT EXISTS ${DB_TEST_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_TEST_USER}'@'localhost' IDENTIFIED BY '${DB_TEST_PASS}';
GRANT ALL PRIVILEGES ON ${DB_TEST_NAME}.* TO '${DB_TEST_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
    else
        echo -e "${YELLOW}Konnte keine Verbindung zur Datenbank herstellen. Das kann bei neuen Installationen normal sein.${NC}"
        echo -e "${YELLOW}Bitte setze ein Root-Passwort für MySQL mit:${NC}"
        echo -e "${GREEN}sudo mysql_secure_installation${NC}"
        echo -e "${YELLOW}Nach Abschluss kannst du MySQL mit folgendem Befehl testen:${NC}"
        echo -e "${GREEN}mysql -u root -p${NC}"
        
        echo -e "${YELLOW}Alternativ kannst du versuchen, MySQL neu zu konfigurieren:${NC}"
        echo -e "${GREEN}sudo dpkg-reconfigure mysql-server-X.Y${NC} oder ${GREEN}sudo dpkg-reconfigure mariadb-server-X.Y${NC}"
    fi
fi

# Zusammenfassung
echo -e "${GREEN}=== MySQL/MariaDB Diagnose abgeschlossen ===${NC}"
echo -e "${YELLOW}Dienst:${NC} ${DB_SERVICE}"
echo -e "${YELLOW}Status:${NC} $(systemctl is-active ${DB_SERVICE} || service ${DB_SERVICE} status | grep -o "running\|active")"
echo -e "${YELLOW}Datenverzeichnis:${NC} ${DATA_DIR}"
echo -e "${YELLOW}Test-Datenbank:${NC} ${DB_TEST_NAME}"
echo -e "${YELLOW}Test-Benutzer:${NC} ${DB_TEST_USER}"
echo -e "${YELLOW}Test-Passwort:${NC} ${DB_TEST_PASS}"

# Nächste Schritte
echo -e "${GREEN}=== Nächste Schritte ===${NC}"
echo -e "1. Wenn MySQL/MariaDB jetzt läuft, kannst du das Nextcloud-Installationsscript erneut ausführen."
echo -e "2. Falls Probleme bestehen, überprüfe die oben genannten Fehlerprotokolle."
echo -e "3. Bei Bedarf, führe eine MySQL-Sicherheitsinstallation aus: ${GREEN}sudo mysql_secure_installation${NC}"

exit 0
