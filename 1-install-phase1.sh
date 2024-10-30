#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ERROR: $1"
    exit 1
}

# Check Docker and Docker Compose
check_dependencies() {
    log "Checking dependencies..."

    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi

    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
    fi

    log "Dependencies verified successfully"
}

# Create project structure
create_project_structure() {
    log "Creating project structure..."
    
    mkdir -p {data/{backup,postgres,redis},config}
    
    log "Project structure created successfully"
}

# Create environment file
create_env_file() {
    log "Creating environment file..."
    
    cat > .env << EOL
# Database Configuration
DB_USER=backup
DB_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
DB_NAME=backupdb
DB_PORT=5432

# Redis Configuration
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
REDIS_PORT=6379

# Storage Paths
BACKUP_PATH=/data/backup
EOL

    chmod 600 .env
    log "Environment file created successfully"
}

# Create docker-compose file
create_docker_compose() {
    log "Creating Docker Compose configuration..."
    
    cat > docker-compose.yml << EOL
version: '3.8'

services:
  db:
    image: postgres:14-alpine
    environment:
      - POSTGRES_USER=\${DB_USER}
      - POSTGRES_PASSWORD=\${DB_PASSWORD}
      - POSTGRES_DB=\${DB_NAME}
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
      - ./config/init.sql:/docker-entrypoint-initdb.d/init.sql
    ports:
      - "\${DB_PORT}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${DB_USER} -d \${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:alpine
    command: redis-server --requirepass \${REDIS_PASSWORD}
    ports:
      - "\${REDIS_PORT}:6379"
    volumes:
      - ./data/redis:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
EOL

    log "Docker Compose configuration created successfully"
}

# Create database initialization script
create_db_schema() {
    log "Creating database schema..."
    
    cat > config/init.sql << EOL
-- Backup Environments
CREATE TABLE IF NOT EXISTS backup_environments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    config JSONB NOT NULL
);

-- Volume Backups
CREATE TABLE IF NOT EXISTS volume_backups (
    id SERIAL PRIMARY KEY,
    volume_name VARCHAR(255) NOT NULL,
    backup_type VARCHAR(50) NOT NULL,
    parent_backup_id INTEGER REFERENCES volume_backups(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    size_bytes BIGINT,
    checksum_map JSONB,
    metadata JSONB,
    status VARCHAR(50) NOT NULL,
    retention_policy JSONB
);

-- Backup Jobs
CREATE TABLE IF NOT EXISTS backup_jobs (
    id SERIAL PRIMARY KEY,
    environment_id INTEGER REFERENCES backup_environments(id),
    schedule VARCHAR(100),
    last_run TIMESTAMP WITH TIME ZONE,
    next_run TIMESTAMP WITH TIME ZONE,
    config JSONB NOT NULL,
    status VARCHAR(50)
);

-- Backup History
CREATE TABLE IF NOT EXISTS backup_history (
    id SERIAL PRIMARY KEY,
    job_id INTEGER REFERENCES backup_jobs(id),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(50) NOT NULL,
    size_bytes BIGINT,
    metadata JSONB,
    error_message TEXT
);
EOL

    log "Database schema created successfully"
}

# Start services and verify
verify_setup() {
    log "Starting services..."
    
    docker-compose up -d
    
    log "Waiting for services to be ready..."
    sleep 10
    
    if ! docker-compose ps | grep -q "db.*Up" || ! docker-compose ps | grep -q "redis.*Up"; then
        error "Services failed to start properly. Check logs with: docker-compose logs"
    fi
    
    log "Services started successfully"
}

# Save credentials
save_credentials() {
    log "Saving credentials..."
    
    source .env
    cat > credentials.txt << EOL
Database User: ${DB_USER}
Database Password: ${DB_PASSWORD}
Database Name: ${DB_NAME}
Database Port: ${DB_PORT}
Redis Password: ${REDIS_PASSWORD}
Redis Port: ${REDIS_PORT}

Please store these credentials securely and delete this file after saving them.
EOL

    chmod 600 credentials.txt
    log "Credentials saved to credentials.txt"
}

# Main installation process
main() {
    log "Starting Phase 1 installation..."
    
    check_dependencies
    create_project_structure
    create_env_file
    create_docker_compose
    create_db_schema
    verify_setup
    save_credentials
    
    log "Phase 1 installation completed successfully!"
    log "Core services are running:"
    log "- PostgreSQL: localhost:${DB_PORT}"
    log "- Redis: localhost:${REDIS_PORT}"
    log ""
    log "Credentials have been saved to credentials.txt"
    log "Please save these credentials securely and delete the file"
}

# Run the installation
main
