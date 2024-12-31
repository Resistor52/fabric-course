#!/bin/bash

# Enable logging
exec 1> >(tee -a /var/log/user-data.log) 2>&1
echo "Setup script started at $(date)"

# Exit immediately if a command exits with a non-zero status
set -e

# Set HOME environment variable and create required directories
export HOME=/home/ubuntu
mkdir -p $HOME
chown ubuntu:ubuntu $HOME

PORT=8080 # Port for code-server (default: 8080)

echo "Starting setup script..."

# Update and install dependencies
echo "Updating system and installing dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y curl software-properties-common ufw nginx certbot python3-certbot-nginx dnsutils

echo "Installing code-server..."
# Install code-server
curl -fsSL https://code-server.dev/install.sh | sudo -u ubuntu sh

echo "Configuring code-server..."
# Configure code-server
mkdir -p $HOME/.config/code-server
chown -R ubuntu:ubuntu $HOME/.config
cat > $HOME/.config/code-server/config.yaml << EOF
bind-addr: 0.0.0.0:$PORT
auth: password
password: ${CODE_SERVER_PASSWORD}
cert: false
EOF
chown ubuntu:ubuntu $HOME/.config/code-server/config.yaml

echo "Enabling code-server service..."
# Enable code-server systemd service
sudo systemctl enable --now code-server@ubuntu

echo "Configuring firewall..."
# Configure firewall
sudo ufw --force enable  # Add --force to prevent prompt
sudo ufw allow OpenSSH
sudo ufw allow $PORT
sudo ufw allow "Nginx Full"

echo "Setting up DuckDNS..."
# Set up DuckDNS for dynamic DNS
cat > $HOME/duckdns_update.sh << EOF
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DOMAIN}&token=${DUCKDNS_TOKEN}&ip=" | curl -k -o ~/duckdns.log -K -
EOF
chmod +x $HOME/duckdns_update.sh
chown ubuntu:ubuntu $HOME/duckdns_update.sh
sudo -u ubuntu $HOME/duckdns_update.sh  # Run immediately
sudo -u ubuntu bash -c "(crontab -l 2>/dev/null; echo \"*/5 * * * * $HOME/duckdns_update.sh\") | crontab -"

# Check DNS propagation
echo "Checking DNS propagation..."
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "Waiting for DNS to propagate to our IP: $PUBLIC_IP"

# More thorough DNS check
for i in {1..30}; do
    echo "DNS check attempt $i of 30"
    # Check using multiple DNS servers
    GOOGLE_DNS=$(dig @8.8.8.8 +short "${DOMAIN}")
    CLOUDFLARE_DNS=$(dig @1.1.1.1 +short "${DOMAIN}")
    
    echo "Current DNS resolution:"
    echo "Google DNS: $GOOGLE_DNS"
    echo "Cloudflare DNS: $CLOUDFLARE_DNS"
    
    if [ "$GOOGLE_DNS" = "$PUBLIC_IP" ] && [ "$CLOUDFLARE_DNS" = "$PUBLIC_IP" ]; then
        echo "DNS propagation confirmed on multiple DNS servers!"
        # Add extra wait to ensure full propagation
        echo "Waiting an additional 30 seconds for full propagation..."
        sleep 30
        break
    fi
    echo "Waiting 20 seconds before next check..."
    sleep 20
done

# Continue with SSL setup regardless
echo "Setting up SSL with Let's Encrypt..."
# Try multiple times for SSL setup
for i in {1..3}; do
    if sudo certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${EMAIL}"; then
        echo "SSL setup successful!"
        break
    else
        echo "SSL setup attempt $i failed. Waiting 30 seconds before retry..."
        sleep 30
    fi
done

echo "Configuring Nginx..."
# Configure Nginx as a reverse proxy
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

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
    }
}
EOF"

echo "Setting up Nginx symlinks..."
# Check and create symbolic link for Nginx configuration
if [ ! -L "/etc/nginx/sites-enabled/${DOMAIN}" ]; then
    sudo ln -s /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
fi

# Remove default Nginx site if it exists
if [ -L "/etc/nginx/sites-enabled/default" ]; then
    sudo rm /etc/nginx/sites-enabled/default
fi

echo "Testing Nginx configuration..."
# Test Nginx configuration
if sudo nginx -t; then
    sudo systemctl reload nginx
else
    echo "Nginx configuration test failed. Please check your configuration."
    exit 1
fi

echo "Final service restarts..."
# Restart services
sudo systemctl restart code-server@ubuntu
sudo systemctl restart nginx

echo "Verifying services..."
# Verify services are running
sudo systemctl status code-server@ubuntu --no-pager
sudo systemctl status nginx --no-pager

# Output access details
echo "Setup complete!"
echo "Access code-server at https://$DOMAIN"
echo "Your password is stored in ~/.config/code-server/config.yaml"

# Add a final sleep to ensure all services are fully started
sleep 10

# After code-server setup
echo "Checking code-server status..."
sudo systemctl status code-server@ubuntu --no-pager
echo "Checking code-server logs..."
sudo journalctl -u code-server@ubuntu --no-pager | tail -n 50

# After nginx setup
echo "Checking nginx status..."
sudo systemctl status nginx --no-pager
echo "Checking nginx error log..."
sudo tail -n 50 /var/log/nginx/error.log 