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

    log "Prerequisites check completed"
}

# Create React app structure
setup_react_app() {
    log "Setting up React application structure..."

    # Create directory structure
    mkdir -p web-ui/{src/{components,contexts,hooks,services,pages,utils},public}

    # Create package.json with required dependencies
    cat > web-ui/package.json << 'EOL'
{
  "name": "backup-system-ui",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.22.3",
    "axios": "^1.6.7",
    "tailwindcss": "^3.4.1",
    "@tailwindcss/forms": "^0.5.7",
    "lucide-react": "^0.358.0",
    "classnames": "^2.5.1",
    "date-fns": "^3.3.1",
    "jwt-decode": "^4.0.0",
    "zustand": "^4.5.2"
  },
  "devDependencies": {
    "react-scripts": "5.0.1",
    "autoprefixer": "^10.4.18",
    "postcss": "^8.4.35",
    "@babel/plugin-transform-private-methods": "^7.23.3",
    "@babel/plugin-transform-class-properties": "^7.23.3",
    "@babel/plugin-transform-numeric-separator": "^7.23.3",
    "@babel/plugin-transform-nullish-coalescing-operator": "^7.23.3",
    "@babel/plugin-transform-optional-chaining": "^7.23.3"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  }
}
EOL

    # Create index.html
    cat > web-ui/public/index.html << 'EOL'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#000000" />
    <meta name="description" content="Backup System Dashboard" />
    <title>Backup System</title>
  </head>
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
  </body>
</html>
EOL

    # Create index.css with Tailwind imports
    cat > web-ui/src/index.css << 'EOL'
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  @apply bg-gray-50;
}

.btn {
  @apply px-4 py-2 rounded-md font-medium focus:outline-none focus:ring-2 focus:ring-offset-2;
}

.btn-primary {
  @apply bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500;
}

.btn-secondary {
  @apply bg-gray-200 text-gray-700 hover:bg-gray-300 focus:ring-gray-500;
}

.input {
  @apply block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500;
}
EOL

    # Create tailwind.config.js
    cat > web-ui/tailwind.config.js << 'EOL'
module.exports = {
  content: [
    "./src/**/*.{js,jsx,ts,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [
    require('@tailwindcss/forms'),
  ],
}
EOL

    log "Basic React structure created"
}

# Create authentication context and store
create_auth_system() {
    log "Creating authentication system..."

    # Create auth store using Zustand
    cat > web-ui/src/stores/authStore.js << 'EOL'
import { create } from 'zustand'

const useAuthStore = create((set) => ({
  isAuthenticated: false,
  user: null,
  authType: 'local', // 'local' or 'ldap'

  login: (userData) => set({ 
    isAuthenticated: true, 
    user: userData 
  }),

  logout: () => set({ 
    isAuthenticated: false, 
    user: null 
  }),

  setAuthType: (type) => set({ 
    authType: type 
  })
}))

export default useAuthStore
EOL

    # Create auth service
    cat > web-ui/src/services/authService.js << 'EOL'
import axios from 'axios';

const AUTH_API = process.env.REACT_APP_API_URL || 'http://localhost:3000/api';

export const authService = {
  async login(credentials, authType = 'local') {
    try {
      // For demo purposes, check local admin credentials
      if (authType === 'local' && 
          credentials.username === 'admin' && 
          credentials.password === 'admin') {
        return {
          user: {
            username: 'admin',
            role: 'admin'
          }
        };
      }

      // For LDAP authentication, we would make an API call
      if (authType === 'ldap') {
        const response = await axios.post(`${AUTH_API}/auth/ldap`, credentials);
        return response.data;
      }

      throw new Error('Invalid credentials');
    } catch (error) {
      throw new Error(error.message || 'Authentication failed');
    }
  },

  logout() {
    // Add any logout logic here (clear tokens, etc.)
  }
};
EOL

    # Create Protected Route component
    cat > web-ui/src/components/ProtectedRoute.js << 'EOL'
import React from 'react';
import { Navigate } from 'react-router-dom';
import useAuthStore from '../stores/authStore';

const ProtectedRoute = ({ children }) => {
  const { isAuthenticated } = useAuthStore();

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return children;
};

export default ProtectedRoute;
EOL

    # Create Login Page
    cat > web-ui/src/pages/Login.js << 'EOL'
import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import useAuthStore from '../stores/authStore';
import { authService } from '../services/authService';

const Login = () => {
  const navigate = useNavigate();
  const { login, setAuthType } = useAuthStore();
  const [authMode, setAuthMode] = useState('local');
  const [credentials, setCredentials] = useState({
    username: '',
    password: ''
  });
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');

    try {
      const response = await authService.login(credentials, authMode);
      login(response.user);
      setAuthType(authMode);
      navigate('/');
    } catch (err) {
      setError(err.message || 'Login failed');
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8">
        <div>
          <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
            Backup System Login
          </h2>
        </div>
        
        {error && (
          <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
            {error}
          </div>
        )}

        <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
          <div className="rounded-md shadow-sm -space-y-px">
            <div>
              <label htmlFor="username" className="sr-only">Username</label>
              <input
                id="username"
                name="username"
                type="text"
                required
                className="input rounded-t-md"
                placeholder="Username"
                value={credentials.username}
                onChange={(e) => setCredentials({
                  ...credentials,
                  username: e.target.value
                })}
              />
            </div>
            <div>
              <label htmlFor="password" className="sr-only">Password</label>
              <input
                id="password"
                name="password"
                type="password"
                required
                className="input rounded-b-md"
                placeholder="Password"
                value={credentials.password}
                onChange={(e) => setCredentials({
                  ...credentials,
                  password: e.target.value
                })}
              />
            </div>
          </div>

          <div>
            <div className="flex items-center mb-4">
              <input
                id="local"
                name="auth-type"
                type="radio"
                checked={authMode === 'local'}
                onChange={() => setAuthMode('local')}
                className="h-4 w-4 text-blue-600"
              />
              <label htmlFor="local" className="ml-2 block text-sm text-gray-900">
                Local Authentication
              </label>
            </div>
            <div className="flex items-center">
              <input
                id="ldap"
                name="auth-type"
                type="radio"
                checked={authMode === 'ldap'}
                onChange={() => setAuthMode('ldap')}
                className="h-4 w-4 text-blue-600"
              />
              <label htmlFor="ldap" className="ml-2 block text-sm text-gray-900">
                LDAP Authentication
              </label>
            </div>
          </div>

          <div>
            <button type="submit" className="btn btn-primary w-full">
              Sign in
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export default Login;
EOL

    log "Authentication system created"
}

# Create main application components
create_app_components() {
    log "Creating application components..."

    # Create App.js with routes
    cat > web-ui/src/App.js << 'EOL'
import React from 'react';
import { Routes, Route } from 'react-router-dom';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import BackupList from './pages/BackupList';
import RestorePoints from './pages/RestorePoints';
import Navigation from './components/Navigation';
import ProtectedRoute from './components/ProtectedRoute';
import useAuthStore from './stores/authStore';

function App() {
  const { isAuthenticated } = useAuthStore();

  return (
    <div className="min-h-screen bg-gray-50">
      {isAuthenticated && <Navigation />}
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/" element={
          <ProtectedRoute>
            <Dashboard />
          </ProtectedRoute>
        } />
        <Route path="/backups" element={
          <ProtectedRoute>
            <BackupList />
          </ProtectedRoute>
        } />
        <Route path="/restore" element={
          <ProtectedRoute>
            <RestorePoints />
          </ProtectedRoute>
        } />
      </Routes>
    </div>
  );
}

export default App;
EOL

    # Create Navigation component
    cat > web-ui/src/components/Navigation.js << 'EOL'
import React from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Home, Database, RefreshCw, LogOut } from 'lucide-react';
import useAuthStore from '../stores/authStore';

const Navigation = () => {
  const navigate = useNavigate();
  const { logout } = useAuthStore();

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  return (
    <nav className="bg-white shadow">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between h-16">
          <div className="flex">
            <div className="flex-shrink-0 flex items-center">
              <span className="text-xl font-bold">Backup System</span>
            </div>
            <div className="hidden sm:ml-6 sm:flex sm:space-x-8">
              <Link
                to="/"
                className="inline-flex items-center px-1 pt-1 text-sm font-medium text-gray-900"
              >
                <Home className="h-4 w-4 mr-2" />
                Dashboard
              </Link>
              <Link
                to="/backups"
                className="inline-flex items-center px-1 pt-1 text-sm font-medium text-gray-900"
              >
                <Database className="h-4 w-4 mr-2" />
                Backups
              </Link>
              <Link
                to="/restore"
                className="inline-flex items-center px-1 pt-1 text-sm font-medium text-gray-900"
              >
                <RefreshCw className="h-4 w-4 mr-2
              </Link>
            </div>
          </div>
          <div className="flex items-center">
            <button
              onClick={handleLogout}
              className="inline-flex items-center px-3 py-2 border border-transparent text-sm font-medium rounded-md text-gray-500 hover:text-gray-700"
            >
              <LogOut className="h-4 w-4 mr-2" />
              Logout
            </button>
          </div>
        </div>
      </div>
    </nav>
  );
};

export default Navigation;
EOL

    # Create Dashboard page
    cat > web-ui/src/pages/Dashboard.js << 'EOL'
import React from 'react';
import { Server, HardDrive, Clock, CheckCircle } from 'lucide-react';

const Dashboard = () => {
  const stats = {
    totalBackups: 0,
    activeBackups: 0,
    lastBackup: null,
    storageUsed: '0%'
  };

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
      <h1 className="text-2xl font-semibold text-gray-900 mb-6">Dashboard</h1>
      
      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
        <div className="bg-white overflow-hidden shadow rounded-lg">
          <div className="p-5">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <Server className="h-6 w-6 text-gray-400" />
              </div>
              <div className="ml-5 w-0 flex-1">
                <dl>
                  <dt className="text-sm font-medium text-gray-500 truncate">
                    Total Backups
                  </dt>
                  <dd className="text-lg font-medium text-gray-900">
                    {stats.totalBackups}
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div className="bg-white overflow-hidden shadow rounded-lg">
          <div className="p-5">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <Clock className="h-6 w-6 text-gray-400" />
              </div>
              <div className="ml-5 w-0 flex-1">
                <dl>
                  <dt className="text-sm font-medium text-gray-500 truncate">
                    Active Backups
                  </dt>
                  <dd className="text-lg font-medium text-gray-900">
                    {stats.activeBackups}
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div className="bg-white overflow-hidden shadow rounded-lg">
          <div className="p-5">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <HardDrive className="h-6 w-6 text-gray-400" />
              </div>
              <div className="ml-5 w-0 flex-1">
                <dl>
                  <dt className="text-sm font-medium text-gray-500 truncate">
                    Storage Used
                  </dt>
                  <dd className="text-lg font-medium text-gray-900">
                    {stats.storageUsed}
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>

        <div className="bg-white overflow-hidden shadow rounded-lg">
          <div className="p-5">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <CheckCircle className="h-6 w-6 text-gray-400" />
              </div>
              <div className="ml-5 w-0 flex-1">
                <dl>
                  <dt className="text-sm font-medium text-gray-500 truncate">
                    Last Backup
                  </dt>
                  <dd className="text-lg font-medium text-gray-900">
                    {stats.lastBackup ? new Date(stats.lastBackup).toLocaleString() : 'Never'}
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
EOL

    # Create BackupList page
    cat > web-ui/src/pages/BackupList.js << 'EOL'
import React from 'react';
import { Plus } from 'lucide-react';

const BackupList = () => {
  const backups = [];

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-semibold text-gray-900">Backups</h1>
        <button className="btn btn-primary inline-flex items-center">
          <Plus className="h-4 w-4 mr-2" />
          New Backup
        </button>
      </div>

      <div className="bg-white shadow overflow-hidden sm:rounded-md">
        <ul className="divide-y divide-gray-200">
          {backups.length === 0 ? (
            <li className="p-4 text-center text-gray-500">
              No backups found. Create your first backup.
            </li>
          ) : (
            backups.map((backup) => (
              <li key={backup.id} className="p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="text-lg font-medium">{backup.name}</h3>
                    <p className="text-sm text-gray-500">
                      {new Date(backup.created_at).toLocaleString()}
                    </p>
                  </div>
                  <div className="flex items-center space-x-4">
                    <span className={`px-2 py-1 rounded-full text-sm ${
                      backup.status === 'completed' 
                        ? 'bg-green-100 text-green-800'
                        : 'bg-yellow-100 text-yellow-800'
                    }`}>
                      {backup.status}
                    </span>
                    <button className="btn btn-secondary">
                      Details
                    </button>
                  </div>
                </div>
              </li>
            ))
          )}
        </ul>
      </div>
    </div>
  );
};

export default BackupList;
EOL

    # Create RestorePoints page
    cat > web-ui/src/pages/RestorePoints.js << 'EOL'
import React from 'react';
import { Clock, RefreshCw } from 'lucide-react';

const RestorePoints = () => {
  const restorePoints = [];

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
      <h1 className="text-2xl font-semibold text-gray-900 mb-6">Restore Points</h1>

      <div className="bg-white shadow overflow-hidden sm:rounded-md">
        <ul className="divide-y divide-gray-200">
          {restorePoints.length === 0 ? (
            <li className="p-4 text-center text-gray-500">
              No restore points available.
            </li>
          ) : (
            restorePoints.map((point) => (
              <li key={point.id} className="p-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center">
                    <Clock className="h-5 w-5 text-gray-400 mr-3" />
                    <div>
                      <h3 className="text-lg font-medium">
                        {new Date(point.timestamp).toLocaleString()}
                      </h3>
                      <p className="text-sm text-gray-500">
                        Size: {point.size}
                      </p>
                    </div>
                  </div>
                  <button className="btn btn-primary inline-flex items-center">
                    <RefreshCw className="h-4 w-4 mr-2" />
                    Restore
                  </button>
                </div>
              </li>
            ))
          )}
        </ul>
      </div>
    </div>
  );
};

export default RestorePoints;
EOL

    log "Application components created"
}

# Create index.js
create_index() {
    log "Creating index.js..."

    cat > web-ui/src/index.js << 'EOL'
import React from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';
import './index.css';

const container = document.getElementById('root');
const root = createRoot(container);

root.render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
);
EOL
}

# Create Dockerfile
create_dockerfile() {
    log "Creating Dockerfile..."

    cat > web-ui/Dockerfile << 'EOL'
# Build stage
FROM node:16-alpine as build

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source files
COPY . .

# Create production build
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy built files
COPY --from=build /app/build /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOL

    # Create nginx.conf
    cat > web-ui/nginx.conf << 'EOL'
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    location /api {
        proxy_pass http://api:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    error_page 404 /index.html;
}
EOL
}

# Update docker-compose configuration
update_docker_compose() {
    log "Updating docker-compose configuration..."

    if ! grep -q "web-ui:" docker-compose.yml; then
        cat >> docker-compose.yml << 'EOL'

  web-ui:
    build: 
      context: ./web-ui
      dockerfile: Dockerfile
    ports:
      - "8080:80"
    environment:
      - REACT_APP_API_URL=http://localhost:3000
    restart: unless-stopped
EOL
    fi
}

# Start services
start_services() {
    log "Building and starting services..."
    
    docker-compose up -d --build web-ui
    
    log "Services started"
}

# Verify installation
verify_installation() {
    log "Verifying installation..."

    sleep 10

    if ! docker-compose ps | grep -q "web-ui.*Up"; then
        error "Web UI failed to start properly. Check logs with: docker-compose logs web-ui"
    fi

    if curl -s http://localhost:8080 > /dev/null; then
        log "Web UI is accessible at http://localhost:8080"
    else
        warning "Web UI is not responding at http://localhost:8080"
    fi

    log "Installation verification completed"
}

# Main installation process
main() {
    log "Starting Web Dashboard setup..."

    check_prerequisites
    setup_react_app
    create_auth_system
    create_app_components
    create_index
    create_dockerfile
    update_docker_compose
    start_services
    verify_installation

    log "Web Dashboard setup completed successfully!"
    log "Dashboard is available at: http://localhost:8080"
    log "Default credentials:"
    log "  Username: admin"
    log "  Password: admin"
    log ""
    log "Please verify:"
    log "1. Login page is accessible"
    log "2. Can login with default credentials"
    log "3. Navigation and components are working"
    log "4. LDAP option is available on login screen"
}

# Run the installation
main
