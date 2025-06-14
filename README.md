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
  <a href="#getting-started">Getting Started</a> •
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
- Blue/green deployments with ability to switch to canary deployments

The deployment process looks like this (you'l need to view this on Github.com to see the diagram):

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

### Local setup

1. Clone the repository:
  ```bash
  git clone https://github.com/zaneriley/personal-site-infra.git
  ```
  
1. Adjust the `scripts/install-setup.sh` file with your correct image registry and version.

1. Run the setup script on your local machine to install the required tools:
  ```bash
    ./run setup <GITHUB_USER>
  ```
  You'll be prompted to enter your GitHub personal access token to enable FluxCD to access your repositories.

1. Set up secrets using Bitnami's Sealed Secrets:
   a. Create a regular Kubernetes secret YAML file locally:

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

1. Apply the FluxCD configuration:
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


## Usage
1. Apply the Kubernetes manifests:
  ```bash
  kubectl apply -f namespace.yaml
  kubectl apply -f deployments.yaml
  kubectl apply -f service-canary.yaml
  kubectl apply -f ingress.yaml
  ```
1.Verify the resources are created
  ```bash
  kubectl get all -n personal-site
  kubectl get ingress -n personal-site
  ```
1.Test accessing the app
   - Add `personal-site.local` to your `/etc/hosts` file, pointing to your cluster IP
   ```bash
   echo "127.0.0.1 personal-site.local" | sudo tee -a /etc/hosts
   ```
   - Type `   kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8000:80`. This command forwards port 80 of the ingress controller to port 8000 on your local machine.
   - Open a browser and navigate to `http://personal-site.local:8000`
   - Verify you see the "Green Version" message

1. Test blue/green switch:
  ```bash
  ./scripts/switch-deployment.sh
  ```

1. Verify the switch:
```bash
  kubectl get ingress personal-site -n personal-site -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'
  ```

  This should now return `personal-site-blue`.

7. Refresh your browser and verify you see the "Blue Version" message.

8. Test canary deployment:
  ```bash
  ./scripts/canary-deploy.sh 20
  ```

1. Verify the canary deployment:
  ```bash
  kubectl get ingress personal-site-canary -n personal-site -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'
  ```
  This should return 20

1. Refresh your browser multiple times. You should see the "Blue Version" message about 80% of the time.

1. Increase the weight to 100 and refresh your browser. You should see the "Green Version" message.

1. Verify the main ingress has switched. 
  ```bash
  kubectl get ingress personal-site -n personal-site -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'
  ```
  This should return `personal-site-green`.

1. Test rollback:
  ```bash
  ./scripts/switch-deployment.sh
  ```

1. Verify the switch:
  ```bash
  kubectl get ingress personal-site -n personal-site -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'
  ```

  This should now return `personal-site-blue`.

1. Cleanup
  ```bash
  kubectl delete namespace personal-site
  ```

## Observability (Prometheus & Grafana)

This project now includes a GitOps-managed observability stack using Prometheus for metrics collection and Grafana for visualization. The setup is deployed via the `kube-prometheus-stack` Helm chart, managed by FluxCD.

### How it Works

FluxCD monitors the `kubernetes/` directory (specifically looking at `kubernetes/kustomization.yaml`, which then includes `kubernetes/observability/kustomization.yaml`). When changes are pushed to this repository, FluxCD will:

1.  Apply the `HelmRepository` resource to make the `prometheus-community` Helm chart repository available.
2.  Apply the `HelmRelease` resource for `kube-prometheus-stack`, which installs Prometheus, Grafana, Alertmanager, and various metrics exporters into the `monitoring` namespace.
3.  Apply the `sealed-grafana-admin-credentials.yaml` (once created by you) to configure the Grafana admin password.
4.  Grafana is configured with a sidecar to automatically discover and import dashboards provided as ConfigMaps with the label `grafana_dashboard: "1"` in the `monitoring` namespace. (Note: The actual creation of these dashboard ConfigMaps is a pending task from the previous automated work session).

### User Setup Steps

There are a couple of manual steps you need to perform for the initial setup:

1.  **Set Grafana Admin Password:**
    A manifest for an unsealed Grafana admin secret is provided at `kubernetes/observability/grafana-admin-credentials-unsealed.yaml`. You **must** edit this file to set a strong password:
    ```yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: grafana-admin-credentials
      namespace: monitoring
    type: Opaque
    stringData:
      adminPassword: "YOUR_STRONG_GRAFANA_PASSWORD" # <-- REPLACE THIS
      adminUser: admin
    ```
    Then, use your `kubeseal` utility to encrypt this secret and save it as `kubernetes/observability/sealed-grafana-admin-credentials.yaml`.
    Example command:
    ```bash
    kubeseal --format=yaml < kubernetes/observability/grafana-admin-credentials-unsealed.yaml > kubernetes/observability/sealed-grafana-admin-credentials.yaml
    ```
    Commit the resulting `sealed-grafana-admin-credentials.yaml` file to the repository. The unsealed version should **not** be committed.

2.  **Verify FluxCD Kustomization:**
    This setup introduced a top-level Kustomization at `kubernetes/kustomization.yaml` which includes the `./base` and `./observability` paths.
    Ensure your FluxCD bootstrap configuration (the `Kustomization` resource that syncs *this* `personal-site-infra` repository) is pointing to this `kubernetes/kustomization.yaml` file, or that it otherwise includes `kubernetes/observability/kustomization.yaml` in its `spec.path`. If Flux was originally bootstrapped to only look at `./kubernetes/base` or specific overlay paths, you might need to update its configuration to include the new observability components.

### Accessing Grafana

Once deployed, you can access Grafana as follows:

*   **Username:** `admin`
*   **Password:** The strong password you set in the `grafana-admin-credentials` secret.

To access the Grafana UI, you can use port-forwarding:

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 9090:80
```

Then, open your browser and navigate to `http://localhost:9090`.

*(Note: The service name for Grafana is typically `<helm-release-name>-grafana`. Since our HelmRelease is named `kube-prometheus-stack`, the service is `kube-prometheus-stack-grafana`.)*

### Available Dashboards (Pending Implementation)

The following dashboards are intended to be automatically imported into Grafana once their ConfigMap definitions are added (this was a pending task from the previous automated work session and still needs to be implemented):

*   **Kubernetes Cluster Overview:** General health and resource usage of the Kubernetes cluster.
*   **Kubernetes Node Overview:** Detailed metrics for individual nodes.
*   **FluxCD Control Plane:** Health and status of FluxCD components and reconciliations.

### Troubleshooting

*   **Check Pod Status:** To see if Prometheus, Grafana, and other components are running:
    ```bash
    kubectl get pods -n monitoring
    ```
*   **Check FluxCD Logs:** If the observability components are not deploying as expected, check the FluxCD controller logs:
    ```bash
    kubectl logs -n flux-system -l app=source-controller
    kubectl logs -n flux-system -l app=kustomize-controller
    kubectl logs -n flux-system -l app=helm-controller
    ```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

Zane Riley - [GitHub](https://github.com/zaneriley)

Personal Site - [GitHub](https://github.com/zaneriley/personal-site) [Website](https://zaneriley.com)

Project Link: [https://github.com/zaneriley/personal-site](https://github.com/zaneriley/personal-site)
