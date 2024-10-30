#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ERROR: $1"
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    error "Please run this script with sudo or as root"
fi

check_phase1() {
    log "Checking Phase 1 installation..."
    
    if [ ! -f ".env" ] || [ ! -f "docker-compose.yml" ]; then
        error "Phase 1 installation not found. Please run Phase 1 installation first."
    fi

    if ! docker-compose ps | grep -q "db.*Up" || ! docker-compose ps | grep -q "redis.*Up"; then
        error "Core services from Phase 1 are not running."
    fi
}

create_directories() {
    log "Creating directories..."
    
    mkdir -p {prometheus/{rules,data},grafana/{data,logs,plugins,provisioning/{datasources,dashboards}},data/grafana,api/src,backup-worker/src,restore-worker/src,scheduler/src,web-ui/public}
}

setup_grafana() {
    log "Setting up Grafana..."
    
    cat > grafana/grafana.ini << 'EOL'
[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning

[server]
http_port = 3000
domain = localhost
root_url = %(protocol)s://%(domain)s:3001

[database]
type = sqlite3
path = /var/lib/grafana/grafana.db

[session]
provider = file
provider_config = sessions

[analytics]
reporting_enabled = false
check_for_updates = true

[security]
admin_user = admin
allow_embedding = true
cookie_secure = false
cookie_samesite = lax

[snapshots]
external_enabled = false

[users]
allow_sign_up = false
allow_org_create = false
auto_assign_org = true
auto_assign_org_role = Editor

[auth.anonymous]
enabled = false

[log]
mode = console
level = info

[metrics]
enabled = true
disable_total_stats = false
EOL

    cat > grafana/provisioning/datasources/prometheus.yml << 'EOL'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    version: 1
EOL

    GRAFANA_USER=472
    GRAFANA_GROUP=472

    chown -R $GRAFANA_USER:$GRAFANA_GROUP grafana/
    chown -R $GRAFANA_USER:$GRAFANA_GROUP data/grafana/
    find grafana/ -type d -exec chmod 755 {} \;
    find data/grafana -type d -exec chmod 755 {} \;
    find grafana/ -type f -exec chmod 644 {} \;
    find data/grafana -type f -exec chmod 644 {} \;
    chmod 777 data/grafana
}

setup_prometheus() {
    log "Setting up Prometheus..."

    cat > prometheus/prometheus.yml << 'EOL'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'backup-api'
    static_configs:
      - targets: ['api:3000']

  - job_name: 'backup-workers'
    static_configs:
      - targets: ['backup-worker:3000', 'restore-worker:3000']
EOL

    chown -R nobody:nobody prometheus
    chmod -R 755 prometheus
}

create_service_files() {
    log "Creating service files..."

    cat > api/src/index.js << 'EOL'
const express = require('express');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());
const port = process.env.PORT || 3000;
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});
app.listen(port, '0.0.0.0', () => {
  console.log(`API running on port ${port}`);
});
EOL

    cat > api/package.json << 'EOL'
{
  "name": "backup-system-api",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node src/index.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5"
  }
}
EOL

    for service in backup-worker restore-worker scheduler; do
        cat > "$service/package.json" << EOL
{
  "name": "${service}",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node src/index.js"
  },
  "dependencies": {
    "pg": "^8.11.3",
    "redis": "^4.6.8"
  }
}
EOL
        cat > "$service/src/index.js" << EOL
console.log('${service} started');
EOL
    done

    cat > web-ui/public/index.html << 'EOL'
<!DOCTYPE html>
<html>
<head>
    <title>Backup System</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; padding: 20px; }
    </style>
</head>
<body>
    <h1>Backup System</h1>
    <p>System is running.</p>
</body>
</html>
EOL
}

create_dockerfiles() {
    log "Creating Dockerfiles..."

    cat > api/Dockerfile << 'EOL'
FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
USER node
EXPOSE 3000
CMD ["npm", "start"]
EOL

    for service in backup-worker restore-worker scheduler; do
        cat > "$service/Dockerfile" << 'EOL'
FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
USER node
CMD ["npm", "start"]
EOL
    done

    cat > web-ui/Dockerfile << 'EOL'
FROM nginx:alpine
COPY public/* /usr/share/nginx/html/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOL
}

update_docker_compose() {
    log "Creating Docker Compose configuration..."
    
    cat > docker-compose.yml << 'EOL'
version: '3.8'

services:
  db:
    image: postgres:14-alpine
    environment:
      - POSTGRES_USER=${DB_USER}
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=${DB_NAME}
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    ports:
      - "${DB_PORT}:5432"

  redis:
    image: redis:alpine
    command: redis-server --requirepass ${REDIS_PASSWORD}
    ports:
      - "${REDIS_PORT}:6379"
    volumes:
      - ./data/redis:/data

  api:
    build: ./api
    user: "node"
    ports:
      - "3000:3000"
    environment:
      - DB_CONNECTION_STRING=postgresql://${DB_USER}:${DB_PASSWORD}@db:5432/${DB_NAME}
      - REDIS_URL=redis://default:${REDIS_PASSWORD}@redis:6379
    depends_on:
      - db
      - redis
    restart: unless-stopped

  backup-worker:
    build: ./backup-worker
    user: "node"
    environment:
      - DB_CONNECTION_STRING=postgresql://${DB_USER}:${DB_PASSWORD}@db:5432/${DB_NAME}
      - REDIS_URL=redis://default:${REDIS_PASSWORD}@redis:6379
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./data/backup:/backup
    depends_on:
      - db
      - redis
    restart: unless-stopped

  restore-worker:
    build: ./restore-worker
    user: "node"
    environment:
      - DB_CONNECTION_STRING=postgresql://${DB_USER}:${DB_PASSWORD}@db:5432/${DB_NAME}
      - REDIS_URL=redis://default:${REDIS_PASSWORD}@redis:6379
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./data/backup:/backup:ro
    depends_on:
      - db
      - redis
    restart: unless-stopped

  scheduler:
    build: ./scheduler
    user: "node"
    environment:
      - DB_CONNECTION_STRING=postgresql://${DB_USER}:${DB_PASSWORD}@db:5432/${DB_NAME}
      - REDIS_URL=redis://default:${REDIS_PASSWORD}@redis:6379
    depends_on:
      - db
      - redis
    restart: unless-stopped

  web-ui:
    build: ./web-ui
    ports:
      - "8080:80"
    depends_on:
      - api
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    user: "65534:65534"
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus:/etc/prometheus:ro
      - ./data/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=${PROMETHEUS_RETENTION:-15d}'
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    user: "472:472"
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    volumes:
      - ./grafana:/etc/grafana:ro
      - ./data/grafana:/var/lib/grafana
    restart: unless-stopped
EOL
}

update_env() {
    log "Updating environment configuration..."
    
    if ! grep -q "GRAFANA_PASSWORD" .env; then
        {
            echo ""
            echo "# Monitoring Configuration"
            echo "GRAFANA_USER=admin"
            echo "GRAFANA_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
            echo "PROMETHEUS_RETENTION=15d"
        } >> .env
    fi
}

start_services() {
    log "Starting services..."
    
    docker-compose pull
    docker-compose up -d --build
    
    log "Waiting for services to start..."
    sleep 30
    
    docker-compose ps
}

main() {
    log "Starting Phase 2 installation..."
    
    check_phase1
    create_directories
    setup_grafana
    setup_prometheus
    create_service_files
    create_dockerfiles
    update_env
    update_docker_compose
    start_services
    
    log "Phase 2 installation completed successfully!"
    log "Services available at:"
    log "- Web UI: http://localhost:8080"
    log "- API: http://localhost:3000"
    log "- Grafana: http://localhost:3001 (admin:${GRAFANA_PASSWORD})"
    log "- Prometheus: http://localhost:9090"
}

main
