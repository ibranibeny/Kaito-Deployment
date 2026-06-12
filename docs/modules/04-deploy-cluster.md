---
layout: default
title: "4. Deploy Cluster"
nav_order: 6
---

# Deploy AKS Cluster with KAITO
{: .no_toc }

Create an AKS cluster with the AI Toolchain Operator enabled.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## 4.1 Set Variables

```bash
export RAND=$RANDOM
export LOCATION="indonesiacentral"
export RG_NAME="rg-kaito-demo-${RAND}"
export AKS_NAME="aks-kaito-${RAND}"

# Save for later steps
cat > ./demo-env.sh << EOF
export RAND=${RAND}
export LOCATION=${LOCATION}
export RG_NAME=${RG_NAME}
export AKS_NAME=${AKS_NAME}
EOF
```

---

## 4.2 Create Resource Group

```bash
az group create --name $RG_NAME --location $LOCATION
```

---

## 4.3 Create AKS with KAITO

This creates an AKS cluster with the AI Toolchain Operator pre-installed:

```bash
az aks create \
    --resource-group $RG_NAME \
    --name $AKS_NAME \
    --location $LOCATION \
    --node-count 1 \
    --node-vm-size Standard_D4s_v3 \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --enable-managed-identity \
    --enable-oidc-issuer \
    --enable-ai-toolchain-operator \
    --generate-ssh-keys
```

{: .note }
> This takes approximately **10 minutes**. The `--enable-ai-toolchain-operator` flag installs KAITO and gpu-provisioner automatically.

### What gets created

| Component | Purpose |
|---|---|
| System node pool (1x D4s_v3) | Runs KAITO controller, CoreDNS, metrics |
| KAITO workspace controller | Watches Workspace CRs, manages lifecycle |
| gpu-provisioner | Provisions GPU nodes on demand |
| OIDC issuer | Enables workload identity for KAITO |
| Azure CNI Overlay | Required networking for node auto-provisioning |

---

## 4.4 Get Credentials

```bash
az aks get-credentials \
    --resource-group $RG_NAME \
    --name $AKS_NAME \
    --overwrite-existing
```

---

## 4.5 Verify KAITO Installation

```bash
# Check nodes
kubectl get nodes

# Verify KAITO pods are running
kubectl get pods -n kube-system | grep kaito

# Check CRDs installed
kubectl get crd | grep kaito
```

Expected output:

```
NAME                              READY   STATUS    AGE
kaito-gpu-provisioner-xxx         1/1     Running   2m
kaito-workspace-xxx               1/1     Running   2m
```

```
workspaces.kaito.sh               2024-01-01T00:00:00Z
```

---

[← Prerequisites]({{ site.baseurl }}{% link modules/03-prerequisites.md %}){: .btn .mr-2 }
[Next: Deploy Model →]({{ site.baseurl }}{% link modules/05-deploy-model.md %}){: .btn .btn-primary }
