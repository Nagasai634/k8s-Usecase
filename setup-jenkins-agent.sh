#!/bin/bash
set -e

echo "=== Setting up Jenkins Agent ==="

# Install kubectl
echo "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Install docker
echo "Installing docker..."
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl start docker
sudo systemctl enable docker

# Add jenkins user to docker group
sudo usermod -aG docker jenkins

# Install gcloud CLI (if not present)
which gcloud || (echo "Installing gcloud..." && sudo apt-get install -y google-cloud-sdk)

# Restart Jenkins to apply group changes
sudo systemctl restart jenkins

echo "=== Setup completed ==="