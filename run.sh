#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit
fi

# Detect package manager
if command -v apt &> /dev/null; then
  PKG_MANAGER="apt"
elif command -v dnf &> /dev/null; then
  PKG_MANAGER="dnf"
else
  echo "Supported package manager not found (apt or dnf required)."
  exit 1
fi

# Detect system architecture
ARCH=$(uname -m)

# Install Docker
echo "Installing Docker..."
if ! [ -x "$(command -v docker)" ]; then
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    sudo apt-get update
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
    sudo apt-get update
    sudo apt-get install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y docker
  fi
  systemctl enable docker
  systemctl start docker
fi

# Install K3s
echo "Installing K3s..."
if [[ "$ARCH" == "aarch64" ]]; then
  if ! [ -x "$(command -v k3s)" ]; then
    curl -sfL https://get.k3s.io | sh -s - --node-name "aarch64-node"
  fi
else
  if ! [ -x "$(command -v k3s)" ]; then
    curl -sfL https://get.k3s.io | sh -
  fi
fi

# Install kubectl
echo "Installing kubectl..."
if ! [ -x "$(command -v kubectl)" ]; then
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install kubectl /usr/local/bin/kubectl
fi

# Configure kubectl for K3s
echo "Configuring kubectl..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if ! kubectl get nodes > /dev/null 2>&1; then
  echo "Error: Unable to connect to Kubernetes API. Restarting K3s..."
  systemctl restart k3s
  sleep 5
fi

# Build the Docker image
echo "Building Docker image for Flask app..."
docker build -t flask-monitor:latest ./flask-app

# Push the image to K3s
echo "Pushing Docker image to K3s..."
ctr images import <(docker save flask-monitor:latest)

# Apply Kubernetes manifests
echo "Deploying Flask app..."
kubectl apply -f ./k8s/deployment.yaml
kubectl apply -f ./k8s/service.yaml

echo "Deploying Prometheus..."
kubectl apply -f ./k8s/prometheus-deployment.yaml

echo "Deploying Grafana..."
kubectl apply -f ./k8s/grafana-deployment.yaml

# Fetch NodePorts and display service URLs
NODE_IP=$(hostname -I | awk '{print $1}')
FLASK_PORT=$(kubectl get svc flask-monitor-service -o=jsonpath='{.spec.ports[0].nodePort}')
PROMETHEUS_PORT=$(kubectl get svc prometheus -o=jsonpath='{.spec.ports[0].nodePort}')
GRAFANA_PORT=$(kubectl get svc grafana -o=jsonpath='{.spec.ports[0].nodePort}')

echo "Services are available at:"
echo "Flask Monitor: http://${NODE_IP}:${FLASK_PORT}"
echo "Prometheus: http://${NODE_IP}:${PROMETHEUS_PORT}"
echo "Grafana: http://${NODE_IP}:${GRAFANA_PORT}"
echo "Grafana login: admin/admin"
