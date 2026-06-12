---
layout: default
title: "3. Prerequisites"
nav_order: 5
---

# Prerequisites
{: .no_toc }

Set up your environment before deploying KAITO.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## 3.1 Azure Subscription

You need an Azure subscription with:

- **Contributor** access to create AKS clusters
- **GPU quota** for `Standard_NV36ads_A10_v5` (at least 36 vCPUs in your target region)

{: .warning }
> Check GPU quota before starting: `az vm list-usage -l indonesiacentral -o table | grep NV`

---

## 3.2 Required Tools

| Tool | Version | Command |
|------|---------|---------|
| Azure CLI | 2.60+ | `az --version` |
| kubectl | 1.28+ | `kubectl version --client` |
| aks-preview extension | latest | `az extension show --name aks-preview` |
| Bash shell | any | Linux, macOS, or WSL |
| jq (optional) | any | `jq --version` |

### Install Azure CLI

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### Install aks-preview extension

```bash
az extension add --name aks-preview --upgrade
```

---

## 3.3 Azure Login

```bash
az login --use-device-code
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

---

## 3.4 Clone the Repository

```bash
git clone https://github.com/ibranibeny/Kaito-Deployment.git
cd Kaito-Deployment
```

---

## 3.5 GPU Quota Check

KAITO requires `Standard_NV36ads_A10_v5` which needs 36 vCPU quota for the NVadsA10v5 family:

```bash
az vm list-usage -l indonesiacentral -o table \
  | grep -i "NVadsA10"
```

If quota is 0, request an increase via the Azure Portal under **Subscriptions → Usage + quotas**.

---

## Checklist

Before proceeding:

- [ ] Azure CLI installed and logged in
- [ ] aks-preview extension installed
- [ ] GPU quota available (36+ vCPUs for NVadsA10v5)
- [ ] Repository cloned
- [ ] Bash shell available (WSL2 or native)

[← Architecture]({{ site.baseurl }}{% link modules/02-architecture.md %}){: .btn .mr-2 }
[Next: Deploy Cluster →]({{ site.baseurl }}{% link modules/04-deploy-cluster.md %}){: .btn .btn-primary }
