# Fabric Course Infrastructure

This repository contains Terraform configurations to automatically deploy a multi-user learning environment for the [Fabric](https://github.com/danielmiessler/fabric) AI tool. The infrastructure is designed to support multiple students, each with their own isolated environment running on AWS.

## Features

- Automated deployment of GPU-enabled EC2 instance (g5.xlarge)
- Multi-user support with isolated environments
- Web-based VS Code (code-server) for each user
- Pre-installed Ollama with Mistral AI model
- NVIDIA GPU support for AI model acceleration
- Automatic SSL/TLS certificate management
- DuckDNS integration for domain management

## Prerequisites

1. AWS CLI installed and configured with appropriate credentials
2. Terraform installed (version 1.0 or later)
3. A DuckDNS account and domain
4. Git

## Quick Start

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd fabric-course
   ```

2. Initialize the backend:
   ```bash
   ./setup-backend.sh
   ```

3. Configure your variables in `terraform.tfvars`:
   ```hcl
   domain          = "your-domain.duckdns.org"
   email           = "your-email@example.com"
   duckdns_token   = "your-duckdns-token"
   number_of_users = 10  # Adjust based on class size
   ```

4. Deploy the infrastructure:
   ```bash
   terraform init
   terraform apply
   ```

5. Monitor the setup progress:
   ```bash
   # SSH into the instance using the provided command
   ssh -i aws3-use1v2.pem ubuntu@<instance-ip>
   
   # Monitor the setup script progress
   sudo tail -f /var/log/user-data.log
   ```
   The setup is complete when you see "Main setup script completed" in the log.

## Access Information

- Each student gets their own environment accessible at:
  `https://your-domain.duckdns.org/studentN/` (where N is their student number)
- Individual passwords are generated for each student and stored in:
  `/home/ubuntu/course-info/student-passwords.md` on the EC2 instance
- SSH access: Use the command provided in the Terraform output

### Pre-installed AI Models

The environment comes with several AI models pre-installed and ready to use:

- **Mistral-7B**
- **Phi4**
- **deepseek-r1:14b**

Students can optionally configure additional AI models by running `fabric --setup` in their environment and providing their own API keys (e.g., for OpenAI, Anthropic). This is not required for basic usage as the local models are pre-installed and ready to use.

## Architecture

- **EC2 Instance**: g5.xlarge with 30GB root volume
- **Networking**: Custom VPC with public subnet
- **Security**: 
  - HTTPS access to code-server
  - SSH access for administration
  - Ollama API port (11434) for local access
- **State Management**: 
  - S3 backend for Terraform state
  - DynamoDB for state locking

## Cleanup

To destroy all resources and clean up:

```bash
./teardown-backend.sh
```

## Security Notes

- Each student environment is password protected
- SSL/TLS encryption for all web traffic
- Firewall rules limit access to necessary ports only
- GPU acceleration support through NVIDIA drivers

## Troubleshooting

1. **Instance Not Accessible**: 
   - Check security group rules
   - Verify DuckDNS configuration
   - Ensure SSL certificate was issued correctly

2. **GPU Not Working**:
   - SSH into instance and run `nvidia-smi`
   - Check system logs for driver issues
   - May require instance reboot after initial setup

3. **Code-server Issues**:
   - Check service status: `systemctl status code-server@studentN`
   - Verify port configurations
   - Check nginx proxy settings

## Contributing

Feel free to submit issues and enhancement requests! 