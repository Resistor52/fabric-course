#!/bin/bash

# Enable logging
exec 1> >(tee -a /var/log/user-data.log) 2>&1
echo "Main setup script started at $(date)"

# Exit immediately if a command exits with a non-zero status
set -e

# Base port for code-server instances (8080-8089)
BASE_PORT=8080
NUM_USERS=10

# Create users and set up their environments
for i in $(seq 1 $NUM_USERS); do
    USER="student$i"
    PORT=$((BASE_PORT + i - 1))
    echo "Setting up user $USER with port $PORT..."

    # Create user
    sudo useradd -m -s /bin/bash "$USER"

    # Set up user's home directory
    USER_HOME="/home/$USER"
    sudo -u "$USER" mkdir -p "$USER_HOME"

    # Add Go environment variables to user's profile
    sudo -u "$USER" cat >> "$USER_HOME/.profile" << 'EOF'
# Golang environment variables
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
EOF
done

# System updates and base installations
echo "Updating system and installing dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl software-properties-common ufw nginx certbot python3-certbot-nginx dnsutils

# Install NVIDIA drivers and CUDA
echo "Installing NVIDIA drivers and CUDA..."
sudo apt-get install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall

# Verify NVIDIA installation
echo "Verifying NVIDIA installation..."
nvidia-smi || echo "Warning: nvidia-smi failed, system may need a reboot"

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

# Install Ollama
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

# Pull and test llama2 model
echo "Pulling mistral model..."
sudo -u ubuntu ollama list
sudo -u ubuntu ollama pull mistral
sudo -u ubuntu ollama list

echo "Testing mistral model with a simple query..."
sudo -u ubuntu ollama run mistral "Say hello and confirm you're working"

# Add Ollama port to firewall
echo "Adding Ollama port to firewall..."
sudo ufw allow 11434/tcp

# Generate passwords and save them
echo "Generating unique passwords for each user..."
mkdir -p /home/ubuntu/course-info
cat > /home/ubuntu/course-info/student-passwords.md << 'EOF'
# Student Access Information

## Code-Server Passwords

EOF

# Install word list if not present
sudo apt-get install -y wamerican

# Function to generate a random word-based password
generate_password() {
    local words=$(shuf -n 3 /usr/share/dict/american-english | tr '[:upper:]' '[:lower:]' | tr '\n' '-')
    echo "${words}secure"
}

# Generate and save passwords for each user
declare -A USER_PASSWORDS
for i in $(seq 1 $NUM_USERS); do
    USER="student$i"
    PASSWORD=$(generate_password)
    USER_PASSWORDS[$USER]=$PASSWORD
    echo "- Student $i: \`$PASSWORD\`" >> /home/ubuntu/course-info/student-passwords.md
done

echo "
## Access URLs

Access your code-server instance at: https://${DOMAIN}/studentN/
(Replace N with your student number)
" >> /home/ubuntu/course-info/student-passwords.md

chown ubuntu:ubuntu -R /home/ubuntu/course-info

# Install and configure code-server for each user
for i in $(seq 1 $NUM_USERS); do
    USER="student$i"
    PORT=$((BASE_PORT + i - 1))
    echo "Setting up code-server for $USER on port $PORT..."
    
    # Install code-server for user
    sudo -u "$USER" curl -fsSL https://code-server.dev/install.sh | sudo -u "$USER" sh
    
    # Configure code-server for user with unique password
    sudo -u "$USER" mkdir -p "/home/$USER/.config/code-server"
    sudo -u "$USER" cat > "/home/$USER/.config/code-server/config.yaml" << EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: ${USER_PASSWORDS[$USER]}
cert: false
EOF

    # Enable code-server service for user
    sudo systemctl enable --now "code-server@$USER"

    # Install and configure Fabric for user
    echo "Setting up Fabric for $USER..."
    sudo -u "$USER" bash -c "source /home/$USER/.profile && go install github.com/danielmiessler/fabric@latest"
    
    # Configure Fabric for user
    sudo -u "$USER" mkdir -p "/home/$USER/.config/fabric"
    sudo -u "$USER" cat > "/home/$USER/.config/fabric/config.json" << 'EOF'
{
  "ollama": {
    "url": "http://127.0.0.1:11434"
  },
  "default_vendor": "ollama",
  "default_model": "mistral",
  "language": "en"
}
EOF
    
    # Set up Fabric environment file
    sudo -u "$USER" cat > "/home/$USER/.config/fabric/.env" << EOF
DEFAULT_VENDOR=Ollama
DEFAULT_MODEL=mistral:latest
PATTERNS_LOADER_GIT_REPO_URL=https://github.com/danielmiessler/fabric.git
PATTERNS_LOADER_GIT_REPO_PATTERNS_FOLDER=patterns
OLLAMA_API_URL=http://localhost:11434
EOF

    # Pull patterns for user
    sudo -u "$USER" bash -c "source /home/$USER/.profile && fabric -U && fabric -l"
done

# Configure Nginx for all users
echo "Configuring Nginx..."
sudo bash -c "cat > /etc/nginx/sites-available/${DOMAIN} <<'EOF'
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

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

# Close the Nginx server block
sudo bash -c "echo '}' >> /etc/nginx/sites-available/${DOMAIN}"

echo "Setting up Nginx symlinks..."
# Check and create symbolic link for Nginx configuration
if [ ! -L "/etc/nginx/sites-enabled/${DOMAIN}" ]; then
    sudo ln -s /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
fi

# Remove default Nginx site if it exists
if [ -L "/etc/nginx/sites-enabled/default" ]; then
    sudo rm /etc/nginx/sites-enabled/default
fi

echo "Setting up DuckDNS..."
# Set up DuckDNS for dynamic DNS
cat > /home/ubuntu/duckdns_update.sh << EOF
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DOMAIN}&token=${DUCKDNS_TOKEN}&ip=" | curl -k -o ~/duckdns.log -K -
EOF
chmod +x /home/ubuntu/duckdns_update.sh
chown ubuntu:ubuntu /home/ubuntu/duckdns_update.sh
sudo -u ubuntu /home/ubuntu/duckdns_update.sh  # Run immediately
sudo -u ubuntu bash -c "(crontab -l 2>/dev/null; echo \"*/5 * * * * /home/ubuntu/duckdns_update.sh\") | crontab -"

# Configure firewall
echo "Configuring firewall..."
sudo ufw --force enable
sudo ufw allow OpenSSH
sudo ufw allow "Nginx Full"
sudo ufw allow 11434/tcp  # Ollama API
for i in $(seq 1 $NUM_USERS); do
    PORT=$((BASE_PORT + i - 1))
    sudo ufw allow $PORT/tcp  # Code-server ports
done

# Set up SSL with Let's Encrypt
echo "Setting up SSL with Let's Encrypt..."
sudo certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}"

echo "Testing Nginx configuration..."
# Test Nginx configuration
if sudo nginx -t; then
    sudo systemctl reload nginx
else
    echo "Nginx configuration test failed. Please check your configuration."
    exit 1
fi

echo "Final service restarts..."
# Restart all services
sudo systemctl restart nginx
for i in $(seq 1 $NUM_USERS); do
    sudo systemctl restart "code-server@student$i"
done

echo "Setup complete!"
echo "Access code-server instances at:"
for i in $(seq 1 $NUM_USERS); do
    echo "Student $i: https://${DOMAIN}/student$i/"
done 