<p align="center">
  <img src="https://github.com/zaneriley/personal-site/blob/main/logo.png" alt="Zane Riley Portfolio Logo" width="500"/>
</p>

# Personal Site Infrastructure (WIP)

<p align="left">
    <img src="https://img.shields.io/github/license/zaneriley/personal-site" alt="GitHub License" />
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

### Local setup

1. Clone the repository:
    ```bash
    git clone https://github.com/zaneriley/personal-site.git
    ```


1. Update the `personal-site.yaml` file with your correct image registry and version.

1. Set up secrets using Bitnami's Sealed Secrets:
   a. Create a regular Kubernetes secret YAML file locally (do not commit this file):

    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
    name: personal-site-secrets
    namespace: personal-site
    type: Opaque
    stringData:
        SECRET_KEY_BASE: your_secret_key_base
        DEV_TOKEN_SALT: your_dev_token_salt
        PROD_TOKEN_SALT: your_prod_token_salt
        POSTGRES_PASSWORD: your_postgres_password
    ```
a. Use kubeseal to encrypt the secret:
   
   ```bash
   kubeseal --format=yaml < secret.yaml > secret.sealed.yaml
   ```
b. Commit and push the `sealed-secret.yaml` file to the repository.

5. Apply the FluxCD configuration:
```bash
kubectl apply -f kubernetes/flux-systems/flux-system.yaml
```
You can run this to check if everything is working:
```bash
flux get kustomizations
flux get sources git
flux get images all
```
6. FluxCD will automatically sync the repository and apply the configurations.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

Zane Riley - [GitHub](https://github.com/zaneriley)

Personal Site - [GitHub](https://github.com/zaneriley/personal-site) [Website](https://zaneriley.com)

Project Link: [https://github.com/zaneriley/personal-site](https://github.com/zaneriley/personal-site)
