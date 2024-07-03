```
ssh username@server
```
```bash
apt update && apt upgrade -y
apt install -y curl apt-transport-https ca-certificates software-properties-common
```

Install docker if you haven't already:
```bash
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker $USER
    systemctl enable docker
    systemctl start docker
else
    echo "Docker is already installed."
fi
```

```bash
if ! command -v k3s &> /dev/null; then
    curl -sfL https://get.k3s.io | sh -
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
else
    echo "k3s is already installed."
fi
```

Install flux cli: