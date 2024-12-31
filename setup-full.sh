#!/bin/bash

# Enable logging
exec 1> >(tee -a /var/log/user-data.log) 2>&1
echo "Main setup script started at $(date)"

# Exit immediately if a command exits with a non-zero status
set -e

# Base port for code-server instances (8080-8089)
BASE_PORT=8080
NUM_USERS=10

# System updates and base installations
echo "Updating system and installing dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl software-properties-common ufw nginx certbot python3-certbot-nginx dnsutils wamerican

# Install Go (required for Fabric)
echo "Installing Go..."
# Remove any existing Go installation
sudo rm -rf /usr/local/go

# Dynamically fetch and install the latest version of Go with checksum verification
echo "Fetching latest Go version..."
LATEST_GO=$(curl -s https://go.dev/VERSION?m=text | head -n1)
echo "Latest Go version: $LATEST_GO"

echo "Downloading Go..."
wget https://go.dev/dl/$LATEST_GO.linux-amd64.tar.gz
CHECKSUM=$(curl -sL "https://dl.google.com/go/$LATEST_GO.linux-amd64.tar.gz.sha256")
echo "Downloaded checksum: $CHECKSUM"
echo "Filename: $LATEST_GO.linux-amd64.tar.gz"

echo "Verifying checksum..."
echo "$CHECKSUM  $LATEST_GO.linux-amd64.tar.gz" | sha256sum --check
echo "Checksum verified, extracting..."
sudo tar -C /usr/local -xzf $LATEST_GO.linux-amd64.tar.gz
rm $LATEST_GO.linux-amd64.tar.gz

# Install and configure Ollama
echo "Installing Ollama..."
curl -fsSL https://ollama.com/install.sh | sh

# Create Ollama systemd service manually
echo "Creating Ollama systemd service..."
cat > /etc/systemd/system/ollama.service << 'EOF'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
Type=simple
User=ubuntu
Environment="HOME=/home/ubuntu"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="OLLAMA_HOST=0.0.0.0"
ExecStart=/usr/local/bin/ollama serve
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Start Ollama service
echo "Starting Ollama service..."
systemctl daemon-reload
systemctl enable ollama
systemctl start ollama

# Wait for Ollama to be ready
echo "Waiting for Ollama to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags >/dev/null; then
        echo "Ollama is ready!"
        break
    fi
    echo "Waiting for Ollama to start... (attempt $i/30)"
    sleep 2
done

# Pull the Mistral model
echo "Pulling Mistral model..."
sudo -u ubuntu ollama pull mistral

# Generate passwords and save them
echo "Creating student passwords file..."
sudo mkdir -p /home/ubuntu/course-info
sudo chown ubuntu:ubuntu /home/ubuntu/course-info

# Create course README
echo "Downloading course README..."
sudo -u ubuntu mkdir -p /home/ubuntu/course-content
sudo chown ubuntu:ubuntu /home/ubuntu/course-content

# Download README with error checking
if ! curl -fsSL https://raw.githubusercontent.com/Resistor52/fabric-course/main/course-readme.md -o /tmp/course-readme.md; then
    echo "✗ Failed to download course-readme.md"
    exit 1
fi

# Copy and set permissions with verbose output
echo "Setting up course README..."
sudo cp /tmp/course-readme.md /home/ubuntu/course-content/course-readme.md
sudo chown ubuntu:ubuntu /home/ubuntu/course-content/course-readme.md
sudo chmod 644 /home/ubuntu/course-content/course-readme.md
rm -f /tmp/course-readme.md

# Verify README exists and has correct permissions
if [ -f /home/ubuntu/course-content/course-readme.md ]; then
    echo "✓ Course README downloaded successfully"
    ls -la /home/ubuntu/course-content/course-readme.md
else
    echo "✗ Failed to create course README"
    ls -la /home/ubuntu/course-content/
    exit 1
fi

echo "Writing initial markdown content..."
sudo -u ubuntu tee /home/ubuntu/course-info/student-passwords.md << 'EOF'
# Student Access Information

Each student has their own environment with unique credentials:

EOF

# Verify file was created
if [ -f /home/ubuntu/course-info/student-passwords.md ]; then
    echo "✓ Password file created successfully"
    ls -l /home/ubuntu/course-info/student-passwords.md
else
    echo "✗ Failed to create password file"
    exit 1
fi

# Function to generate a random word-based password
generate_password() {
    local words=$(shuf -n 3 /usr/share/dict/american-english | tr '[:upper:]' '[:lower:]' | tr '\n' '-')
    echo "${words}secure"
}

# Create first student user and set up their environment
echo "Setting up first user student1..."
USER="student1"
PORT=$BASE_PORT

# Create user
sudo useradd -m -s /bin/bash "$USER"
USER_HOME="/home/$USER"

# Add Go environment variables to user's profile
sudo -u "$USER" cat >> "$USER_HOME/.profile" << 'EOF'
# Golang environment variables
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
EOF

# Install and configure code-server for first user
echo "Setting up code-server for $USER..."
sudo -u "$USER" mkdir -p "$USER_HOME/.cache/code-server"
sudo -u "$USER" curl -fL https://github.com/coder/code-server/releases/download/v4.96.2/code-server_4.96.2_amd64.deb -o "$USER_HOME/.cache/code-server/code-server_4.96.2_amd64.deb"
DEBIAN_FRONTEND=noninteractive sudo -E dpkg -i "$USER_HOME/.cache/code-server/code-server_4.96.2_amd64.deb"
rm -f "$USER_HOME/.cache/code-server/code-server_4.96.2_amd64.deb"

# Verify code-server installation
if ! which code-server > /dev/null; then
    echo "✗ code-server installation failed"
    exit 1
fi
echo "✓ code-server installed successfully"

# Configure code-server for first user
sudo -u "$USER" mkdir -p "$USER_HOME/.config/code-server"
PASSWORD=$(generate_password)

# Create and configure workspace
sudo -u "$USER" mkdir -p "$USER_HOME/workspace"
echo "Copying course README for student1..."
if ! sudo cp /home/ubuntu/course-content/course-readme.md "$USER_HOME/workspace/"; then
    echo "✗ Failed to copy course README for student1"
    ls -la /home/ubuntu/course-content/
    exit 1
fi
sudo chown "$USER:$USER" "$USER_HOME/workspace/course-readme.md"

# Configure VS Code settings for dark theme
sudo -u "$USER" mkdir -p "$USER_HOME/.local/share/code-server/User"
sudo -u "$USER" cat > "$USER_HOME/.local/share/code-server/User/settings.json" << 'EOF'
{
    "workbench.colorTheme": "Default Dark+",
    "workbench.startupEditor": "readme",
    "editor.fontSize": 14,
    "terminal.integrated.fontSize": 14,
    "workbench.colorCustomizations": {
        "terminal.background": "#1E1E1E"
    }
}
EOF

# Configure workspace
sudo -u "$USER" mkdir -p "$USER_HOME/.local/share/code-server/Machine"
sudo -u "$USER" cat > "$USER_HOME/.local/share/code-server/Machine/settings.json" << EOF
{
    "folder.uri": "file:///home/$USER/workspace"
}
EOF

# Configure code-server with custom assets path
sudo -u "$USER" cat > "$USER_HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $PASSWORD
cert: false
user-data-dir: /home/$USER/.local/share/code-server
extensions-dir: /home/$USER/.local/share/code-server/extensions
EOF

# Create systemd override
sudo mkdir -p /etc/systemd/system/code-server@${USER}.service.d
sudo cat > /etc/systemd/system/code-server@${USER}.service.d/override.conf << EOF
[Service]
Environment="VSCODE_PROXY_URI={{root}}"
Environment="CS_DISABLE_FILE_DOWNLOADS=false"
Environment="CS_DISABLE_GETTING_STARTED_OVERRIDE=1"
Environment="CS_DISABLE_TELEMETRY=1"
Environment="CS_USER_DATA_DIR=/home/$USER/.local/share/code-server"
EOF

# Add student 1 info to markdown
echo "Adding student 1 info to markdown..."
sudo -u ubuntu tee -a /home/ubuntu/course-info/student-passwords.md << EOF

## Student 1
- **URL**: https://${DOMAIN}/student1/
- **Password**: \`$PASSWORD\`
EOF

# Verify the append worked
if ! grep -q "Student 1" /home/ubuntu/course-info/student-passwords.md; then
    echo "✗ Failed to add student 1 info to password file"
    exit 1
fi

# Install and configure Fabric for first user
sudo -u "$USER" bash -c "source $USER_HOME/.profile && go install github.com/danielmiessler/fabric@latest"
sudo -u "$USER" mkdir -p "$USER_HOME/.config/fabric"
sudo -u "$USER" cat > "$USER_HOME/.config/fabric/config.json" << 'EOF'
{
  "ollama": {
    "url": "http://127.0.0.1:11434"
  },
  "default_vendor": "ollama",
  "default_model": "mistral",
  "language": "en"
}
EOF

sudo -u "$USER" cat > "$USER_HOME/.config/fabric/.env" << EOF
DEFAULT_VENDOR=Ollama
DEFAULT_MODEL=mistral:latest
PATTERNS_LOADER_GIT_REPO_URL=https://github.com/danielmiessler/fabric.git
PATTERNS_LOADER_GIT_REPO_PATTERNS_FOLDER=patterns
OLLAMA_API_URL=http://localhost:11434
EOF

# Download patterns for first user
echo "Downloading patterns for $USER..."
if ! sudo -u "$USER" bash -c "source $USER_HOME/.profile && fabric -U"; then
    echo "✗ Failed to download Fabric patterns"
    echo "This is not critical, patterns can be downloaded later"
fi

# Verify Fabric installation
if sudo -u "$USER" bash -c "source $USER_HOME/.profile && which fabric" > /dev/null; then
    echo "✓ Fabric installed successfully"
else
    echo "✗ Fabric installation failed"
    exit 1
fi

# Enable code-server service for first user
sudo systemctl enable --now "code-server@$USER"

# Clone the configuration for remaining users
for i in $(seq 2 $NUM_USERS); do
    USER="student$i"
    PORT=$((BASE_PORT + i - 1))
    echo "Cloning configuration for $USER with port $PORT..."

    # Create user and base directories
    sudo useradd -m -s /bin/bash "$USER"
    sudo mkdir -p "/home/$USER/workspace"
    sudo mkdir -p "/home/$USER/workspace/.vscode"
    sudo mkdir -p "/home/$USER/.config"
    sudo mkdir -p "/home/$USER/.config/fabric"
    sudo mkdir -p "/home/$USER/.config/code-server"
    sudo mkdir -p "/home/$USER/.local"
    sudo mkdir -p "/home/$USER/.local/share/code-server/User"
    sudo mkdir -p "/home/$USER/.local/share/code-server/Machine"
    sudo mkdir -p "/home/$USER/.local/share/code-server/extensions"
    
    # Copy course README
    echo "Copying course README for $USER..."
    if ! sudo cp /home/ubuntu/course-content/course-readme.md "/home/$USER/workspace/"; then
        echo "✗ Failed to copy course README for $USER"
        ls -la /home/ubuntu/course-content/
        exit 1
    fi
    sudo chown "$USER:$USER" "/home/$USER/workspace/course-readme.md"
    echo "✓ Course README copied successfully for $USER"
    
    # Copy configurations
    echo "Copying configurations for $USER..."
    if ! sudo cp -r /home/student1/.config/* "/home/$USER/.config/"; then
        echo "✗ Failed to copy .config for $USER"
        exit 1
    fi
    if ! sudo cp -r /home/student1/.local/* "/home/$USER/.local/"; then
        echo "✗ Failed to copy .local for $USER"
        exit 1
    fi
    if ! sudo cp /home/student1/.profile "/home/$USER/"; then
        echo "✗ Failed to copy .profile for $USER"
        exit 1
    fi
    
    # Fix ownership
    echo "Setting permissions for $USER..."
    sudo chown -R "$USER:$USER" "/home/$USER"

    # Update code-server config with unique port and password
    PASSWORD=$(generate_password)
    
    # Configure code-server with custom assets path
    sudo -u "$USER" cat > "/home/$USER/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $PASSWORD
cert: false
user-data-dir: /home/$USER/.local/share/code-server
extensions-dir: /home/$USER/.local/share/code-server/extensions
EOF

    # Configure workspace settings
    sudo -u "$USER" cat > "/home/$USER/.local/share/code-server/Machine/settings.json" << EOF
{
    "folder.uri": "file:///home/$USER/workspace"
}
EOF

    # Create systemd override
    sudo mkdir -p /etc/systemd/system/code-server@${USER}.service.d
    sudo cat > /etc/systemd/system/code-server@${USER}.service.d/override.conf << EOF
[Service]
Environment="VSCODE_PROXY_URI={{root}}"
Environment="CS_DISABLE_FILE_DOWNLOADS=false"
Environment="CS_DISABLE_GETTING_STARTED_OVERRIDE=1"
Environment="CS_DISABLE_TELEMETRY=1"
Environment="CS_USER_DATA_DIR=/home/$USER/.local/share/code-server"
EOF

    # Add student info to markdown
    echo "Adding student $i info to markdown..."
    sudo -u ubuntu tee -a /home/ubuntu/course-info/student-passwords.md << EOF

## Student $i
- **URL**: https://${DOMAIN}/student$i/
- **Password**: \`$PASSWORD\`
EOF

    # Enable code-server service for user
    sudo systemctl enable --now "code-server@$USER"
done

chown ubuntu:ubuntu -R /home/ubuntu/course-info

# Configure firewall first
echo "Configuring firewall..."
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https
sudo ufw allow 11434/tcp  # Ollama API
for i in $(seq 1 $NUM_USERS); do
    PORT=$((BASE_PORT + i - 1))
    sudo ufw allow $PORT/tcp  # Code-server ports
done

# Configure Nginx for all users (HTTP first)
echo "Configuring Nginx for HTTP..."

# Create custom login style file
echo "Creating custom login styles..."
sudo mkdir -p /etc/nginx/code-server/
sudo tee /etc/nginx/code-server/custom-login.css << EOF
body { background-color: #1e1e1e !important; color: #ffffff !important; }
.login-form { max-width: 400px !important; margin: 60px auto !important; padding: 20px !important; background-color: #2d2d2d !important; border-radius: 8px !important; }
h1 { color: #4a9eff !important; text-align: center !important; margin-bottom: 30px !important; }
.note { color: #bbbbbb !important; margin: 20px 0 !important; text-align: center !important; }
.submit-button { background-color: #4a9eff !important; }
EOF

sudo bash -c "cat > /etc/nginx/sites-available/${DOMAIN} <<'EOF'
server {
    listen 80;
    server_name ${DOMAIN};

    # Root location block for main site
    location / {
        return 200 'Welcome to Fabric Course. Please use your assigned subdirectory.';
    }

    # Serve custom login CSS
    location /custom-login.css {
        alias /etc/nginx/code-server/custom-login.css;
    }
EOF"

# Add location blocks for each user
for i in $(seq 1 $NUM_USERS); do
    PORT=$((BASE_PORT + i - 1))
    sudo bash -c "cat >> /etc/nginx/sites-available/${DOMAIN} <<EOF
    
    location /student$i/ {
        proxy_pass http://localhost:$PORT/;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \\\$http_upgrade;
        proxy_set_header Connection upgrade;
        sub_filter '</head>' '<link rel="stylesheet" href="/custom-login.css"></head>';
        sub_filter_once on;
    }
EOF"
done

# Close the server block
sudo bash -c "echo '}' >> /etc/nginx/sites-available/${DOMAIN}"

# Enable the site
sudo ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test and start nginx
echo "Testing nginx configuration..."
sudo nginx -t
echo "Starting nginx..."
sudo systemctl restart nginx

# Update DuckDNS and wait for propagation
echo "Updating DuckDNS..."
DOMAIN_PREFIX=$(echo $DOMAIN | cut -d. -f1)
curl "https://www.duckdns.org/update?domains=${DOMAIN_PREFIX}&token=${DUCKDNS_TOKEN}&ip="

# Verify domain is accessible
echo "Verifying domain is accessible..."
for i in {1..6}; do
    echo "Attempt $i: Checking if $DOMAIN is accessible..."
    if curl -s -m 10 "http://${DOMAIN}" > /dev/null; then
        echo "Domain is accessible!"
        break
    else
        echo "Domain not yet accessible, waiting 10 seconds..."
        sleep 10
    fi
done

# Get SSL certificate
echo "Getting SSL certificate from Let's Encrypt..."
sudo certbot --nginx -d ${DOMAIN} --non-interactive --agree-tos --email ${EMAIL} --redirect

# Final testing
echo "Performing final tests..."

# Test Ollama
echo "Testing Ollama service..."
if curl -s http://localhost:11434/api/tags > /dev/null; then
    echo "✓ Ollama service is running"
else
    echo "✗ Ollama service is not responding"
fi

# Test each student's code-server instance
echo -e "\nTesting code-server instances..."
for i in $(seq 1 $NUM_USERS); do
    echo "Testing student$i environment..."
    
    # Test code-server
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "https://${DOMAIN}/student$i/")
    if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "302" ]; then
        echo "✓ code-server for student$i is accessible"
    else
        echo "✗ code-server for student$i returned status $RESPONSE"
    fi
    
    # Test if service is running
    if systemctl is-active --quiet code-server@student$i; then
        echo "✓ code-server@student$i service is running"
    else
        echo "✗ code-server@student$i service is not running"
    fi
done

# Verify credentials file
echo -e "\nVerifying credentials file..."
CREDS_FILE="/home/ubuntu/course-info/student-passwords.md"
if [ -f "$CREDS_FILE" ]; then
    echo "✓ Credentials file exists"
    
    # Check file permissions
    if [ "$(stat -c %U:%G $CREDS_FILE)" = "ubuntu:ubuntu" ]; then
        echo "✓ File has correct ownership"
    else
        echo "✗ Incorrect file ownership: $(stat -c %U:%G $CREDS_FILE)"
    fi
    
    # Check content
    if grep -q "Student ${NUM_USERS}" "$CREDS_FILE"; then
        echo "✓ File contains all student entries"
        echo "File contents:"
        echo "----------------------------------------"
        cat "$CREDS_FILE"
        echo "----------------------------------------"
    else
        echo "✗ File appears to be missing some student entries"
    fi
else
    echo "✗ Credentials file not found!"
fi

echo -e "\nSetup completed at $(date)"
echo "Student credentials are available in: $CREDS_FILE" 

# Test and reload nginx
sudo nginx -t && sudo systemctl reload nginx 