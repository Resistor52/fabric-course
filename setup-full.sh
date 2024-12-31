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

# Generate passwords and save them
echo "Creating student passwords file..."
mkdir -p /home/ubuntu/course-info
cat > /home/ubuntu/course-info/student-passwords.md << 'EOF'
# Student Access Information

Each student has their own environment with unique credentials:

EOF

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

# Configure code-server for first user
sudo -u "$USER" mkdir -p "$USER_HOME/.config/code-server"
PASSWORD=$(generate_password)

# Add student 1 info to markdown
cat >> /home/ubuntu/course-info/student-passwords.md << EOF

## Student 1
- **URL**: https://${DOMAIN}/student1/
- **Password**: \`$PASSWORD\`
EOF

sudo -u "$USER" cat > "$USER_HOME/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $PASSWORD
cert: false
EOF

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
sudo -u "$USER" bash -c "source $USER_HOME/.profile && fabric -U"

# Enable code-server service for first user
sudo systemctl enable --now "code-server@$USER"

# Clone the configuration for remaining users
for i in $(seq 2 $NUM_USERS); do
    USER="student$i"
    PORT=$((BASE_PORT + i - 1))
    echo "Cloning configuration for $USER with port $PORT..."

    # Create user and copy home directory structure
    sudo useradd -m -s /bin/bash "$USER"
    sudo cp -r /home/student1/. "/home/$USER/"
    sudo chown -R "$USER:$USER" "/home/$USER"

    # Update code-server config with unique port and password
    PASSWORD=$(generate_password)
    
    # Add student info to markdown
    cat >> /home/ubuntu/course-info/student-passwords.md << EOF

## Student $i
- **URL**: https://${DOMAIN}/student$i/
- **Password**: \`$PASSWORD\`
EOF

    sudo -u "$USER" cat > "/home/$USER/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: $PASSWORD
cert: false
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
sudo bash -c "cat > /etc/nginx/sites-available/${DOMAIN} <<'EOF'
server {
    listen 80;
    server_name ${DOMAIN};

    # Root location block for main site
    location / {
        return 200 'Welcome to Fabric Course. Please use your assigned subdirectory.';
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

echo -e "\nSetup completed at $(date)"
echo "Student credentials are available in: /home/ubuntu/course-info/student-passwords.md" 