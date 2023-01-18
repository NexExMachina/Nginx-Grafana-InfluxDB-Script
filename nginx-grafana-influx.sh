#!/bin/bash

# Nginx, Grafana, and InfluxDB Installer Script (v.2.0.3) by lilciv#2944
# Built using Docker and Docker Compose.

#Root user check
RootCheck() {
    if [ "$EUID" -ne 0 ]
      then echo "Current user is not root! Please rerun this script as the root user."
      exit
    else
      Dependencies
    fi
}

#Install Docker & Docker Compose
Dependencies() {
    sudo apt install ca-certificates curl gnupg lsb-release -y
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install docker-ce docker-ce-cli containerd.io -y
    sudo apt install docker-compose-plugin -y
    DBCreds
}

#Get InfluxDB Credentials
DBCreds() {
    clear
    echo
    read -p 'InfluxDB Username: ' dbuser
    read -sp 'InfluxDB Password: ' dbpass
    dbadminpass="$(tr -dc '[:alpha:]' < /dev/urandom | fold -w ${1:-20} | head -n1)"
    DomainNames
}

#Get Domain Names
DomainNames() {
    clear
    echo
    read -p 'Grafana Domain (eg. grafana.example.com): ' grafanadomain
    read -p 'InfluxDB Domain (eg. influx.example.com): ' influxdomain
    SSLChoice
}

#Determine HTTP or HTTPS
SSLChoice() {
    echo
    read -n1 -p "Use SSL? [y,n]" choice 
    case $choice in  
      y|Y) SSL ;; 
      n|N) NginxBuildNoSSL ;; 
      *) exit ;; 
    esac
}

#Deploy acme.sh and obtain Let's Encrypt certificate
SSL() {
    clear
    docker stop acme.sh && docker rm acme.sh
    docker run -d --restart unless-stopped \
      -v "$(pwd)"/Docker/Volumes/acme.sh:/acme.sh \
      --net=host \
      --restart unless-stopped \
      --name=acme.sh \
      neilpang/acme.sh daemon
    docker exec acme.sh --set-default-ca --server letsencrypt
    docker exec acme.sh --issue -d $grafanadomain -d $influxdomain --standalone
    echo
    echo
    read -n1 -p "Did your certificate obtain correctly? [y,n]" correct
    case $correct in  
      y|Y) NginxBuild ;; 
      n|N) SSL ;; 
      *) exit ;; 
    esac
}

#Build Nginx
NginxBuild() {
    cat > certrenew.sh << EOF
#!/bin/bash
    docker stop Nginx
    docker exec acme.sh --renew -d $grafanadomain -d $influxdomain
    docker start Nginx
EOF
    chmod +x certrenew.sh
    mkdir -p Docker/Volumes/Nginx/etc/nginx/conf.d
    mkdir -p Docker/Volumes/Nginx/etc/nginx/includes
    mkdir -p Docker/Volumes/Nginx/var/www/html
    mkdir -p Docker/Volumes/Nginx/var/logs
    cat > Docker/Volumes/Nginx/var/www/html/notfound.html << EOF
<meta http-equiv="refresh" content="0; URL='https://$grafanadomain'" />
EOF
    cat > Docker/Volumes/Nginx/etc/nginx/conf.d/default.conf << EOF
server_tokens off;

server {
    listen 80;
    server_name $grafanadomain;
    return 301 https://$grafanadomain$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $grafanadomain;

    ssl_certificate /etc/acme.sh/$grafanadomain/fullchain.cer;
    ssl_certificate_key /etc/acme.sh/$grafanadomain/$grafanadomain.key;
    include /etc/nginx/includes/ssl.conf;

    location / {
    include /etc/nginx/includes/proxy.conf;
    proxy_pass http://Grafana:3000;
    }

    access_log /var/log/nginx/grafana.access.log;
    error_log /var/log/nginx/error.log error;
}

server {
    listen 80;
    server_name $influxdomain;
    return 301 https://$influxdomain$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $influxdomain;

    ssl_certificate /etc/acme.sh/$grafanadomain/fullchain.cer;
    ssl_certificate_key /etc/acme.sh/$grafanadomain/$grafanadomain.key;
    include /etc/nginx/includes/ssl.conf;
    

    location / {
        include /etc/nginx/includes/proxy.conf;
        proxy_pass https://InfluxDB:8086;
    }

    access_log off;
    error_log /var/log/nginx/error.log error;
}

server {
    listen 80 default_server;
    server_name _;
    root /var/www/html;
    
    charset UTF-8;
    
    error_page 404 /notfound.html;
    location = /notfound.html {
        allow all;
    }
    location / {
        return 404;
    }

    log_not_found off;
    error_log /var/log/nginx/error.log error;
}

server {
    listen 443 ssl http2 default_server;
    server_name _;
	
    ssl_certificate /etc/acme.sh/$grafanadomain/$grafanadomain.cer;
    ssl_certificate_key /etc/acme.sh/$grafanadomain/$grafanadomain.key;
	
    root /var/www/html;
    
    charset UTF-8;
    
    error_page 404 /notfound.html;
    location = /notfound.html {
        allow all;
    }
    location / {
        return 404;
    }

    log_not_found off;
    error_log /var/log/nginx/error.log error;
}

EOF
    cat > Docker/Volumes/Nginx/etc/nginx/includes/proxy.conf << EOF
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
proxy_buffering off;
proxy_request_buffering off;
proxy_http_version 1.1;
proxy_intercept_errors on;
EOF
    cat > Docker/Volumes/Nginx/etc/nginx/includes/ssl.conf << EOF
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;
ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHAECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS';
ssl_prefer_server_ciphers on;
EOF
    NginxDeploy
}

#Deploy Nginx
NginxDeploy() {
    cat > docker-compose.yml << EOF
version: '3.8'
services:
  nginx:
    image: nginx:1.22.0-alpine
    container_name: Nginx
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./Docker/Volumes/acme.sh:/etc/acme.sh
      - ./Docker/Volumes/Nginx/var/log/nginx:/var/log/nginx
      - ./Docker/Volumes/Nginx/etc/nginx/conf.d:/etc/nginx/conf.d
      - ./Docker/Volumes/Nginx/etc/nginx/includes:/etc/nginx/includes
      - ./Docker/Volumes/Nginx/var/www/html:/var/www/html
    restart: unless-stopped
networks:
  default:
    name: web
EOF
    docker compose up -d
    rm docker-compose.yml
    InfluxDB
}

#Build Nginx (No SSL)
NginxBuildNoSSL() {
    mkdir -p Docker/Volumes/Nginx/etc/nginx/conf.d
    mkdir -p Docker/Volumes/Nginx/etc/nginx/includes
    mkdir -p Docker/Volumes/Nginx/var/www/html
    mkdir -p Docker/Volumes/Nginx/var/logs
    cat > Docker/Volumes/Nginx/var/www/html/notfound.html << EOF
<meta http-equiv="refresh" content="0; URL='http://$grafanadomain'" />
EOF
    cat > Docker/Volumes/Nginx/etc/nginx/conf.d/default.conf << EOF
server_tokens off;

server {
    listen 80;
    server_name $grafanadomain;

    location / {
    include /etc/nginx/includes/proxy.conf;
    proxy_pass http://Grafana:3000;
    }

    access_log /var/log/nginx/grafana.access.log;
    error_log /var/log/nginx/error.log error;
}

server {
    listen 80;
    server_name $influxdomain;

    location / {
        include /etc/nginx/includes/proxy.conf;
        proxy_pass https://InfluxDB:8086;
    }

    access_log off;
    error_log /var/log/nginx/error.log error;
}

server {
    listen 80 default_server;
    server_name _;
    root /var/www/html;
    
    charset UTF-8;
    
    error_page 404 /notfound.html;
    location = /notfound.html {
        allow all;
    }
    location / {
        return 404;
    }

    log_not_found off;
    error_log /var/log/nginx/error.log error;
}

EOF
    cat > Docker/Volumes/Nginx/etc/nginx/includes/proxy.conf << EOF
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
proxy_buffering off;
proxy_request_buffering off;
proxy_http_version 1.1;
proxy_intercept_errors on;
EOF
    NginxDeployNoSSL
}

#Deploy Nginx (No SSL)
NginxDeployNoSSL() {
    cat > docker-compose.yml << EOF
version: '3.8'
services:
  nginx:
    image: nginx:1.22.0-alpine
    container_name: Nginx
    ports:
      - 80:80
    volumes:
      - ./Docker/Volumes/Nginx/var/log/nginx:/var/log/nginx
      - ./Docker/Volumes/Nginx/etc/nginx/conf.d:/etc/nginx/conf.d
      - ./Docker/Volumes/Nginx/etc/nginx/includes:/etc/nginx/includes
      - ./Docker/Volumes/Nginx/var/www/html:/var/www/html
    restart: unless-stopped
networks:
  default:
    name: web
EOF
    docker compose up -d
    rm docker-compose.yml
    InfluxDB
}

#Deploy InfluxDB
InfluxDB() {
    docker run -d --network web --name InfluxDB --log-opt max-size=50m --restart unless-stopped -v "$(pwd)"/Docker/Volumes/InfluxDB/etc/ssl:/etc/ssl -v "$(pwd)"/Docker/Volumes/InfluxDB/influxdb:/var/lib/influxdb -e INFLUXDB_DB=db01 -e INFLUXDB_HTTP_AUTH_ENABLED=true -e INFLUXDB_USER=$dbuser -e INFLUXDB_USER_PASSWORD=$dbpass -e INFLUXDB_ADMIN_USER=influxadmin -e INFLUXDB_ADMIN_PASSWORD=$dbadminpass -e INFLUXDB_HTTP_HTTPS_ENABLED=true -e INFLUXDB_HTTP_HTTPS_CERTIFICATE="/etc/ssl/fullchain.pem" -e INFLUXDB_HTTP_HTTPS_PRIVATE_KEY="/etc/ssl/privkey.pem" -e INFLUXDB_DATA_MAX_VALUES_PER_TAG=0 -e INFLUXDB_DATA_MAX_SERIES_PER_DATABASE=0 influxdb:1.8
    Grafana
}

#Deploy Grafana
Grafana() {
    docker run -d --user 0 --restart unless-stopped --network web --name Grafana -v "$(pwd)"/Docker/Volumes/Grafana:/var/lib/grafana grafana/grafana:9.0.7
    SelfSignedCert
}

#Generate Self-Signed Certificate For InfluxDB
SelfSignedCert() {
    cd Docker/Volumes/InfluxDB/etc/ssl
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=NA/ST=NA/L=NA/O=NA/CN=influxdb.local" -keyout privkey.pem -out fullchain.pem
    Finish
}

Finish() {
    docker restart InfluxDB
    docker restart Grafana
    docker restart Nginx
    docker exec InfluxDB influx -unsafeSsl -ssl -username influxadmin -password $dbadminpass -execute 'ALTER RETENTION POLICY "autogen" ON "db01" DURATION 12w SHARD DURATION 24h'
    clear
    echo
    echo Installation complete!
    echo
    echo Your InfluxDB database name is db01
    echo
    echo
    echo IF YOU CHOSE TO USE SSL, in 60 days, please run ./certrenew.sh to renew your SSL certificate! 
    echo If you fail to do this, you will receive certificate errors when it expires.
    echo
    echo Your Grafana dashboard is located at http://$grafanadomain
    echo Your InfluxDB instance is located at http://$influxdomain
    echo
}

RootCheck
