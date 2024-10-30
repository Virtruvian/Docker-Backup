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
    
    if [ ! -f "docker-compose.yml" ]; then
        error "docker-compose.yml not found. Please run this script from the backup-system directory."
    fi

    if ! command -v docker-compose &> /dev/null; then
        error "docker-compose is not installed"
    fi

    log "Prerequisites check completed"
}

# Create Duplicati directories
create_directories() {
    log "Creating Duplicati directories..."

    mkdir -p {data/duplicati/{config,backups},duplicati/config}
    
    # Set permissions
    chown -R 1000:1000 data/duplicati
    chmod -R 755 data/duplicati

    log "Directories created successfully"
}

# Create Duplicati configuration
create_duplicati_config() {
    log "Creating Duplicati configuration..."

    # Basic configuration file
    cat > duplicati/config/duplicati-config.json << 'EOL'
{
  "backup_retention": "7D",
  "backup_interval": "24h",
  "compression_method": "zip",
  "encryption_method": "aes-256-cbc",
  "volume_size": "50mb"
}
EOL

    # Set permissions
    chmod 644 duplicati/config/duplicati-config.json

    log "Configuration created successfully"
}

# Update docker-compose.yml
update_docker_compose() {
    log "Updating docker-compose.yml..."

    # Backup existing docker-compose.yml
    cp docker-compose.yml docker-compose.yml.bak

    # Add Duplicati service to docker-compose.yml
    if ! grep -q "duplicati:" docker-compose.yml; then
        cat >> docker-compose.yml << 'EOL'

  duplicati:
    image: duplicati/duplicati:latest
    container_name: backup-duplicati
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    volumes:
      - ./data/duplicati/config:/config
      - ./data/duplicati/backups:/backups
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./duplicati/config:/duplicati-config:ro
    ports:
      - "8200:8200"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8200"]
      interval: 30s
      timeout: 10s
      retries: 3
EOL
    fi

    log "docker-compose.yml updated successfully"
}

# Update environment file
update_env() {
    log "Updating environment configuration..."
    
    if ! grep -q "DUPLICATI_" .env; then
        cat >> .env << EOL

# Duplicati Configuration
DUPLICATI_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
DUPLICATI_PORT=8200
EOL
    fi

    log "Environment configuration updated"
}

# Start Duplicati
start_duplicati() {
    log "Starting Duplicati..."

    docker-compose pull duplicati
    docker-compose up -d duplicati

    # Wait for service to be ready
    log "Waiting for Duplicati to start..."
    sleep 10

    # Check if service is running
    if ! docker-compose ps | grep -q "duplicati.*Up"; then
        error "Duplicati failed to start properly. Check logs with: docker-compose logs duplicati"
    fi

    log "Duplicati started successfully"
}

# Configure backup storage paths
configure_backup_paths() {
    log "Configuring backup storage paths..."

    # Create source paths if they don't exist
    mkdir -p data/backups/{files,databases,volumes}
    
    # Set permissions
    chown -R 1000:1000 data/backups
    chmod -R 755 data/backups

    log "Backup paths configured successfully"
}

# Verify installation
verify_installation() {
    log "Verifying Duplicati installation..."

    # Check if Duplicati web interface is accessible
    if curl -s http://localhost:8200 > /dev/null; then
        log "Duplicati web interface is accessible"
    else
        warning "Duplicati web interface is not responding"
    fi

    # Check if backup directories are properly set up
    if [ -d "data/duplicati/config" ] && [ -d "data/duplicati/backups" ]; then
        log "Backup directories are properly set up"
    else
        warning "Backup directories may not be properly configured"
    fi

    log "Installation verification completed"
}

# Main installation process
main() {
    log "Starting Duplicati setup..."

    check_prerequisites
    create_directories
    create_duplicati_config
    update_docker_compose
    update_env
    configure_backup_paths
    start_duplicati
    verify_installation

    log "Duplicati setup completed successfully!"
    log "Duplicati web interface available at: http://localhost:8200"
    log "Configuration stored in: ./duplicati/config"
    log "Backups will be stored in: ./data/duplicati/backups"
}

# Run the installation
main
