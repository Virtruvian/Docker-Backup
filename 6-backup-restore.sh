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

    # Check if required services are running
    services=("duplicati" "api" "web-ui")
    for service in "${services[@]}"; do
        if ! docker-compose ps | grep -q "${service}.*Up"; then
            error "Service $service is not running. Please ensure all required services are up."
        fi
    done

    log "Prerequisites check completed"
}

# Create API endpoints for backup/restore
setup_api_endpoints() {
    log "Setting up API endpoints..."

    # Create API routes directory
    mkdir -p api/src/routes

    # Create backup routes
    cat > api/src/routes/backup.js << 'EOL'
const express = require('express');
const router = express.Router();
const axios = require('axios');

// Get all backups
router.get('/backups', async (req, res) => {
    try {
        const response = await axios.get('http://duplicati:8200/api/v1/backups');
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: 'Failed to fetch backups' });
    }
});

// Create new backup
router.post('/backups', async (req, res) => {
    try {
        const response = await axios.post('http://duplicati:8200/api/v1/backup/create', req.body);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: 'Failed to create backup' });
    }
});

// Get backup status
router.get('/backups/:id/status', async (req, res) => {
    try {
        const response = await axios.get(`http://duplicati:8200/api/v1/backup/${req.params.id}/status`);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: 'Failed to get backup status' });
    }
});

module.exports = router;
EOL

    # Create restore routes
    cat > api/src/routes/restore.js << 'EOL'
const express = require('express');
const router = express.Router();
const axios = require('axios');

// Get restore points
router.get('/restore-points', async (req, res) => {
    try {
        const response = await axios.get('http://duplicati:8200/api/v1/restorepoints');
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: 'Failed to fetch restore points' });
    }
});

// Start restore
router.post('/restore', async (req, res) => {
    try {
        const response = await axios.post('http://duplicati:8200/api/v1/restore', req.body);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: 'Failed to start restore' });
    }
});

// Get restore status
router.get('/restore/:id/status', async (req, res) => {
    try {
        const response = await axios.get(`http://duplicati:8200/api/v1/restore/${req.params.id}/status`);
        res.json(response.data);
    } catch (error) {
        res.status(500).json({ error: 'Failed to get restore status' });
    }
});

module.exports = router;
EOL

    log "API endpoints created successfully"
}

# Set up backup service
setup_backup_service() {
    log "Setting up backup service..."

    # Create backup service file
    mkdir -p api/src/services
    cat > api/src/services/backup.js << 'EOL'
const axios = require('axios');
const { promisify } = require('util');
const exec = promisify(require('child_process').exec);

class BackupService {
    constructor() {
        this.duplicatiUrl = 'http://duplicati:8200';
    }

    async createBackup(options) {
        const {
            name,
            source,
            destination,
            schedule,
            retention
        } = options;

        try {
            const response = await axios.post(`${this.duplicatiUrl}/api/v1/backup/create`, {
                name,
                source,
                destination,
                schedule,
                retention
            });

            return response.data;
        } catch (error) {
            throw new Error(`Failed to create backup: ${error.message}`);
        }
    }

    async listBackups() {
        try {
            const response = await axios.get(`${this.duplicatiUrl}/api/v1/backups`);
            return response.data;
        } catch (error) {
            throw new Error(`Failed to list backups: ${error.message}`);
        }
    }

    async getBackupStatus(backupId) {
        try {
            const response = await axios.get(`${this.duplicatiUrl}/api/v1/backup/${backupId}/status`);
            return response.data;
        } catch (error) {
            throw new Error(`Failed to get backup status: ${error.message}`);
        }
    }
}

module.exports = new BackupService();
EOL

    log "Backup service setup completed"
}

# Set up restore service
setup_restore_service() {
    log "Setting up restore service..."

    # Create restore service file
    cat > api/src/services/restore.js << 'EOL'
const axios = require('axios');

class RestoreService {
    constructor() {
        this.duplicatiUrl = 'http://duplicati:8200';
    }

    async getRestorePoints() {
        try {
            const response = await axios.get(`${this.duplicatiUrl}/api/v1/restorepoints`);
            return response.data;
        } catch (error) {
            throw new Error(`Failed to get restore points: ${error.message}`);
        }
    }

    async startRestore(options) {
        const {
            restorePoint,
            destination,
            options: restoreOptions
        } = options;

        try {
            const response = await axios.post(`${this.duplicatiUrl}/api/v1/restore`, {
                restorePoint,
                destination,
                options: restoreOptions
            });

            return response.data;
        } catch (error) {
            throw new Error(`Failed to start restore: ${error.message}`);
        }
    }

    async getRestoreStatus(restoreId) {
        try {
            const response = await axios.get(`${this.duplicatiUrl}/api/v1/restore/${restoreId}/status`);
            return response.data;
        } catch (error) {
            throw new Error(`Failed to get restore status: ${error.message}`);
        }
    }
}

module.exports = new RestoreService();
EOL

    log "Restore service setup completed"
}

# Update API package.json
update_api_dependencies() {
    log "Updating API dependencies..."

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
    "axios": "^1.5.0",
    "cors": "^2.8.5",
    "body-parser": "^1.20.2",
    "winston": "^3.10.0"
  }
}
EOL

    log "API dependencies updated"
}

# Update main API file
update_api_main() {
    log "Updating main API file..."

    cat > api/src/index.js << 'EOL'
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const backupRoutes = require('./routes/backup');
const restoreRoutes = require('./routes/restore');

const app = express();

app.use(cors());
app.use(bodyParser.json());

// Routes
app.use('/api/backup', backupRoutes);
app.use('/api/restore', restoreRoutes);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

const port = process.env.PORT || 3000;
app.listen(port, '0.0.0.0', () => {
  console.log(`API running on port ${port}`);
});
EOL

    log "API main file updated"
}

# Rebuild API service
rebuild_api() {
    log "Rebuilding API service..."

    docker-compose stop api
    docker-compose rm -f api
    docker-compose up -d --build api

    log "API service rebuilt"
}

# Verify setup
verify_setup() {
    log "Verifying setup..."

    # Wait for API to start
    sleep 10

    # Check API health
    if curl -s http://localhost:3000/health | grep -q "ok"; then
        log "API is healthy"
    else
        warning "API is not responding properly"
    fi

    # Check backup endpoints
    if curl -s http://localhost:3000/api/backup/backups > /dev/null; then
        log "Backup endpoints are accessible"
    else
        warning "Backup endpoints are not responding"
    fi

    # Check restore endpoints
    if curl -s http://localhost:3000/api/restore/restore-points > /dev/null; then
        log "Restore endpoints are accessible"
    else
        warning "Restore endpoints are not responding"
    fi

    log "Setup verification completed"
}

# Main setup process
main() {
    log "Starting backup/restore setup..."

    check_prerequisites
    setup_api_endpoints
    setup_backup_service
    setup_restore_service
    update_api_dependencies
    update_api_main
    rebuild_api
    verify_setup

    log "Backup/restore setup completed successfully!"
    log "API endpoints available at:"
    log "- Backup endpoints: http://localhost:3000/api/backup/*"
    log "- Restore endpoints: http://localhost:3000/api/restore/*"
}

# Run the setup
main
