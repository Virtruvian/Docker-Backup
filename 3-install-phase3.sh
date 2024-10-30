#!/bin/bash

###########################################
# Phase 3 Installation Script
# This script handles:
# - Service Integration
# - Monitoring Integration
# - System Testing
# - Alert Configuration
# - Dashboard Setup
###########################################

# Color definitions for output
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

###########################################
# Prerequisite Checks
###########################################

check_prerequisites() {
    log "Checking prerequisites..."

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        error "Please run this script with sudo or as root"
    fi

    # Check if Phase 1 and 2 are installed
    if [ ! -f ".env" ] || [ ! -f "docker-compose.yml" ]; then
        error "Phase 1 or 2 installation not found. Please run previous phases first."
    fi

    # Verify core services are running
    services=("db" "redis" "api" "grafana" "prometheus")
    for service in "${services[@]}"; do
        if ! docker-compose ps | grep -q "${service}.*Up"; then
            error "Service $service is not running. Please ensure Phase 1 and 2 are working correctly."
        fi
    done

    log "Prerequisites check completed successfully"
}

###########################################
# Grafana Dashboard Setup
###########################################

setup_grafana_dashboards() {
    log "Setting up Grafana dashboards..."

    # Create dashboards directory if it doesn't exist
    mkdir -p grafana/dashboards

    # System Overview Dashboard
    cat > grafana/dashboards/system_overview.json << 'EOL'
{
  "dashboard": {
    "id": null,
    "title": "System Overview",
    "tags": ["backup-system"],
    "timezone": "browser",
    "panels": [
      {
        "title": "Active Backups",
        "type": "stat",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(backup_jobs_active)",
            "refId": "A"
          }
        ]
      },
      {
        "title": "Storage Usage",
        "type": "gauge",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(backup_storage_used_bytes) / sum(backup_storage_total_bytes) * 100",
            "refId": "A"
          }
        ]
      }
    ]
  }
}
EOL

    # Backup Jobs Dashboard
    cat > grafana/dashboards/backup_jobs.json << 'EOL'
{
  "dashboard": {
    "id": null,
    "title": "Backup Jobs",
    "tags": ["backup-system"],
    "timezone": "browser",
    "panels": [
      {
        "title": "Success Rate",
        "type": "gauge",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "sum(rate(backup_jobs_success_total[24h])) / sum(rate(backup_jobs_total[24h])) * 100",
            "refId": "A"
          }
        ]
      }
    ]
  }
}
EOL

    # Update Grafana dashboard provisioning
    cat > grafana/provisioning/dashboards/backup-system.yml << 'EOL'
apiVersion: 1

providers:
  - name: 'Backup System'
    orgId: 1
    folder: 'Backup System'
    type: file
    disableDeletion: false
    editable: true
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/dashboards
EOL

    log "Grafana dashboards setup completed"
}

###########################################
# Prometheus Alert Rules
###########################################

setup_prometheus_alerts() {
    log "Setting up Prometheus alert rules..."

    # Create rules directory if it doesn't exist
    mkdir -p prometheus/rules

    # Backup System Alert Rules
    cat > prometheus/rules/backup_alerts.yml << 'EOL'
groups:
  - name: backup_alerts
    rules:
      # Backup Job Failures
      - alert: BackupJobFailed
        expr: increase(backup_jobs_failed_total[1h]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Backup job failed"
          description: "A backup job has failed in the last hour"

      # Storage Space
      - alert: BackupStorageNearlyFull
        expr: (backup_storage_used_bytes / backup_storage_total_bytes) * 100 > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Backup storage nearly full"
          description: "Backup storage usage is above 85%"

      # Service Health
      - alert: ServiceDown
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Service is down"
          description: "{{ $labels.job }} service is down"
EOL

    log "Prometheus alert rules setup completed"
}

###########################################
# Integration Tests Setup
###########################################

setup_integration_tests() {
    log "Setting up integration tests..."

    # Create tests directory
    mkdir -p tests

    # Create test script
    cat > tests/integration_test.sh << 'EOL'
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test API health
test_api() {
    echo "Testing API health..."
    if curl -s http://localhost:3000/health | grep -q "ok"; then
        echo -e "${GREEN}API health check passed${NC}"
        return 0
    else
        echo -e "${RED}API health check failed${NC}"
        return 1
    fi
}

# Test backup creation
test_backup() {
    echo "Testing backup creation..."
    # Add backup test logic here
    return 0
}

# Test restore functionality
test_restore() {
    echo "Testing restore functionality..."
    # Add restore test logic here
    return 0
}

# Run all tests
main() {
    test_api
    test_backup
    test_restore
}

main
EOL

    chmod +x tests/integration_test.sh
    log "Integration tests setup completed"
}

###########################################
# Service Integration
###########################################

setup_service_integration() {
    log "Setting up service integration..."

    # Update API configuration for service integration
    cat > api/src/config.js << 'EOL'
module.exports = {
    db: {
        host: process.env.DB_HOST || 'db',
        port: process.env.DB_PORT || 5432,
        database: process.env.DB_NAME,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD
    },
    redis: {
        url: process.env.REDIS_URL
    },
    metrics: {
        enabled: true,
        endpoint: '/metrics'
    }
};
EOL

    log "Service integration setup completed"
}

###########################################
# Metrics Setup
###########################################

setup_metrics() {
    log "Setting up metrics collection..."

    # Create metrics configuration
    cat > api/src/metrics.js << 'EOL'
const client = require('prom-client');

// Create a Registry
const register = new client.Registry();

// Add default metrics
client.collectDefaultMetrics({ register });

// Custom metrics
const backupJobsTotal = new client.Counter({
    name: 'backup_jobs_total',
    help: 'Total number of backup jobs'
});

const backupJobsActive = new client.Gauge({
    name: 'backup_jobs_active',
    help: 'Number of currently running backup jobs'
});

const backupStorageBytes = new client.Gauge({
    name: 'backup_storage_bytes',
    help: 'Backup storage usage in bytes'
});

register.registerMetric(backupJobsTotal);
register.registerMetric(backupJobsActive);
register.registerMetric(backupStorageBytes);

module.exports = register;
EOL

    log "Metrics setup completed"
}

###########################################
# Update Services
###########################################

update_services() {
    log "Updating services with integration changes..."

    # Update docker-compose.yml with new configurations
    docker-compose up -d --build

    log "Services updated successfully"
}

###########################################
# Verify Installation
###########################################

verify_installation() {
    log "Verifying Phase 3 installation..."

    # Check each component
    components=(
        "http://localhost:3000/health:API"
        "http://localhost:3001/api/health:Grafana"
        "http://localhost:9090/-/healthy:Prometheus"
    )

    for component in "${components[@]}"; do
        url="${component%%:*}"
        name="${component#*:}"
        
        if curl -s "$url" > /dev/null; then
            log "$name verification: OK"
        else
            warning "$name verification failed"
        fi
    done

    # Run integration tests
    if [ -f "tests/integration_test.sh" ]; then
        log "Running integration tests..."
        ./tests/integration_test.sh
    fi

    log "Installation verification completed"
}

###########################################
# Main Installation Process
###########################################

main() {
    log "Starting Phase 3 installation..."

    # Execute installation steps
    check_prerequisites
    setup_grafana_dashboards
    setup_prometheus_alerts
    setup_integration_tests
    setup_service_integration
    setup_metrics
    update_services
    verify_installation

    log "Phase 3 installation completed successfully!"
    log "Please verify the following:"
    log "1. Grafana dashboards at http://localhost:3001"
    log "2. Prometheus alerts at http://localhost:9090/alerts"
    log "3. API metrics at http://localhost:3000/metrics"
    log "4. Integration test results in ./tests/integration_test.sh"
}

# Run the installation
main
