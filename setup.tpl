#!/bin/bash

# Enable logging
exec 1> >(tee -a /var/log/user-data.log) 2>&1
echo "Setup script started at $(date)"

# Exit immediately if a command exits with a non-zero status
set -e

# Download and run the main setup script
echo "Downloading main setup script..."
curl -fsSL https://raw.githubusercontent.com/Resistor52/fabric-course/refs/heads/main/setup-full.sh -o /tmp/setup-full.sh
chmod +x /tmp/setup-full.sh

# Export variables for the main script
export DOMAIN="${DOMAIN}"
export EMAIL="${EMAIL}"
export DUCKDNS_TOKEN="${DUCKDNS_TOKEN}"
export NUM_USERS="${NUM_USERS}"

# Run the main script
echo "Running main setup script..."
/tmp/setup-full.sh 