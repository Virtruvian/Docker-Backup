#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ERROR: $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} WARNING: $1"
}

# Check if running as root/sudo
if [ "$EUID" -ne 0 ]; then
    error "Please run this script with sudo or as root"
fi

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if OpenSSL is installed
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install OpenSSL first."
    fi

    # Check if required directories exist
    if [ ! -f "docker-compose.yml" ]; then
        error "docker-compose.yml not found. Please run this script from the backup-system directory."
    fi

    log "Prerequisites check completed"
}

# Create SSL directory structure
create_ssl_directories() {
    log "Creating SSL directory structure..."
    
    mkdir -p ssl/{certs,private,csr}
    chmod 700 ssl/private

    log "SSL directories created"
}

# Generate SSL certificates
generate_ssl_certificates() {
    log "Generating SSL certificates..."

    # Generate root CA
    openssl genrsa -out ssl/private/rootCA.key 4096

    openssl req -x509 -new -nodes \
        -key ssl/private/rootCA.key \
        -sha256 -days 1024 \
        -out ssl/certs/rootCA.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=Backup System Root CA"

    # Generate certificates for each service
    services=("web-ui" "grafana" "prometheus" "api" "duplicati")
    
    for service in "${services[@]}"; do
        log "Generating certificate for $service..."
        
        # Generate private key
        openssl genrsa -out ssl/private/$service.key 2048
        
        # Generate CSR
        openssl req -new \
            -key ssl/private/$service.key \
            -out ssl/csr/$service.csr \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=$service.local"

        # Generate certificate
        openssl x509 -req \
            -in ssl/csr/$service.csr \
            -CA ssl/certs/rootCA.crt \
            -CAkey ssl/private/rootCA.key \
            -CAcreateserial \
            -out ssl/certs/$service.crt \
            -days 365 \
            -sha256
            
        # Create combined PEM file for services that need it
        cat ssl/certs/$service.crt ssl/private/$service.key > ssl/private/$service.pem
        chmod 600 ssl/private/$service.pem
    done

    log "SSL certificates generated successfully"
}

# Configure Nginx with SSL
configure_nginx_ssl() {
    log "Configuring Nginx with SSL..."

    cat > web-ui/nginx.conf << 'EOL'
server {
    listen 80;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name localhost;

    ssl_certificate /etc/nginx/ssl/web-ui.crt;
    ssl_certificate_key /etc/nginx/ssl/web-ui.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    ssl_session_cache shared:SSL:20m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
        auth_basic "Restricted Access";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }

    location /api {
        proxy_pass https://api:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_ssl_verify off;
    }
}
EOL

    log "Nginx SSL configuration completed"
}

# Configure basic authentication
setup_basic_auth() {
    log "Setting up basic authentication..."

    # Generate random password for admin user
    ADMIN_PASS=$(openssl rand -base64 12)

    # Create .htpasswd file for nginx
    docker run --rm -v $PWD/web-ui:/auth apache2-utils htpasswd -cb /auth/.htpasswd admin "$ADMIN_PASS"

    # Store credentials in .env file
    {
        echo "# Basic Auth Credentials"
        echo "BASIC_AUTH_USER=admin"
        echo "BASIC_AUTH_PASS=$ADMIN_PASS"
    } >> .env

    log "Basic authentication configured with username: admin, password: $ADMIN_PASS"
}

# Update docker-compose for SSL
update_docker_compose() {
    log "Updating docker-compose.yml for SSL..."

    # Backup existing configuration
    cp docker-compose.yml docker-compose.yml.bak

    # Add SSL configurations to services
    sed -i '/web-ui:/,/restart: unless-stopped/c\  web-ui:\n    build: ./web-ui\n    ports:\n      - "443:443"\n      - "80:80"\n    volumes:\n      - ./ssl/certs/web-ui.crt:/etc/nginx/ssl/web-ui.crt:ro\n      - ./ssl/private/web-ui.key:/etc/nginx/ssl/web-ui.key:ro\n      - ./web-ui/.htpasswd:/etc/nginx/.htpasswd:ro\n    restart: unless-stopped' docker-compose.yml

    # Update other services with SSL
    for service in "grafana" "prometheus" "api" "duplicati"; do
        if grep -q "$service:" docker-compose.yml; then
            sed -i "/$service:/,/volumes:/a\      - ./ssl/certs/$service.crt:/etc/ssl/$service.crt:ro\n      - ./ssl/private/$service.key:/etc/ssl/$service.key:ro" docker-compose.yml
        fi
    done

    log "Docker Compose updated with SSL configurations"
}

# Configure Grafana SSL
configure_grafana_ssl() {
    log "Configuring Grafana SSL..."

    # Update Grafana configuration
    cat >> grafana/grafana.ini << EOL

[server]
protocol = https
cert_file = /etc/ssl/grafana.crt
cert_key = /etc/ssl/grafana.key
EOL

    log "Grafana SSL configuration completed"
}

# Configure Prometheus SSL
configure_prometheus_ssl() {
    log "Configuring Prometheus SSL..."

    # Update Prometheus configuration for SSL
    sed -i '/command:/a\      - "--web.certificate-path=/etc/ssl/prometheus.crt"\n      - "--web.private-key-path=/etc/ssl/prometheus.key"' docker-compose.yml

    log "Prometheus SSL configuration completed"
}

# Restart services
restart_services() {
    log "Restarting services with SSL..."

    docker-compose down
    docker-compose up -d

    log "Services restarted"
}

# Verify SSL setup
verify_ssl() {
    log "Verifying SSL setup..."

    services=(
        "https://localhost:443"
        "https://localhost:3000"
        "https://localhost:9090"
    )

    for url in "${services[@]}"; do
        if curl -k -s "$url" > /dev/null; then
            log "SSL verification successful for $url"
        else
            warning "SSL verification failed for $url"
        fi
    done

    log "SSL verification completed"
}

# Main setup process
main() {
    log "Starting Phase 4 security setup..."

    check_prerequisites
    create_ssl_directories
    generate_ssl_certificates
    configure_nginx_ssl
    setup_basic_auth
    update_docker_compose
    configure_grafana_ssl
    configure_prometheus_ssl
    restart_services
    verify_ssl

    log "Phase 4 security setup completed successfully!"
    log "Please note the following:"
    log "1. Web UI is now accessible via HTTPS (https://localhost)"
    log "2. Basic auth credentials:"
    log "   - Username: admin"
    log "   - Password: $ADMIN_PASS"
    log "3. Self-signed certificates are located in the ssl/ directory"
    log "4. SSL is enabled for all services"
    log ""
    log "Important: Save these credentials securely!"
}

# Run the setup
main
