<p align="center">
  <img src="https://github.com/zaneriley/personal-site/blob/main/logo.png" alt="Zane Riley Portfolio Logo" width="500"/>
</p>

# Personal Site Infrastructure (WIP)

<p align="left">
    <img src="https://img.shields.io/github/license/zaneriley/personal-site-infra" alt="GitHub License" />
</p>

<p align="left">
  <a href="#introduction">Introduction</a> •
  <a href="#features">Features</a> •
  <a href="#technical-details">Technical Details</a> •
  <a href="#development-and-deployment">Development and Deployment</a> •
  <a href="#future-improvements">Future Improvements</a> •
  <a href="#license">License</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#contact">Contact</a>
</p>

## Introduction

Infrastructure-as-code for my personal website ([Github](https://github.com/zaneriley/personal-site)). It uses Kubernetes and FluxCD  for continuous deployment and infrastructure management. It's an over the top way to launch what is essentially a static website. B

**Why all this for a website?**
- It's a personal website, so why not? It's one of the few times you can build what you want without compromises. 
- It'll be reusable for future app development
- This is also a homelab project. 

## Features

- GitOps-based infrastructure management using FluxCD
- Separate configurations for staging and production
- For production, it uses blue/green deployments

```mermaid
graph TD
    A[Me] -->|Push changes| B[Personal Site Repo]
    A -->|Update infra| C[Personal Site Infra Repo]
    B -->|Trigger build| D[CI/CD Pipeline]
    D -->|Push image| E[Container Registry]
    C -->|Watched by| F[FluxCD]
    F -->|Sync| G[Kubernetes Cluster]
    G -->|Deploy to| H[Staging Environment]
    H -->|Manual Approval| I[Production Environment]
    E -->|Pull image| G
    I -->|Route traffic| J[Blue Deployment]
    I -->|Route traffic| K[Green Deployment]
    L[Ingress Controller] -->|Route external traffic| I
    N[Secrets Management] -->|Provide secrets| G
    I -->|Rollback if issues| H
```

## Installation

<p align="left">
  <img src="https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white" alt="Kubernetes" />
  <img src="https://img.shields.io/badge/FluxCD-316192?style=flat&logo=flux&logoColor=white" alt="FluxCD" />
  <img src="https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white" alt="Docker" />
</p>


### Prerequisites

- Kubernetes cluster
- kubectl configured to access your cluster
- FluxCD installed on your cluster

### Setup

1. Clone the repository:
```bash
git clone https://github.com/zaneriley/personal-site-infra.git
```

2. Set up kubeseal on your local machine. For example, on Ubuntu:
```bash
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/kubeseal-0.18.0-linux-amd64.tar.gz
tar -xvzf kubeseal-0.18.0-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

2. Update the `personal-site.yml` file with your correct image registry and version.

3. Apply the FluxCD configuration:
```bash
kubectl apply -f kubernetes/flux-systems/flux-system.yml
```

4. FluxCD will automatically sync the repository and apply the configurations.


## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

Zane Riley - [GitHub](https://github.com/zaneriley)

Personal Site - [GitHub](https://github.com/zaneriley/personal-site) [Website](https://zaneriley.com)

Project Link: [https://github.com/zaneriley/personal-site-infra](https://github.com/zaneriley/personal-site-infra)
