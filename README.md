# Deploy AI Models with KAITO and Headlamp - Demo Guide

> **Official Documentation**: [KAITO AI Toolchain Operator for AKS](https://learn.microsoft.com/en-us/azure/aks/aks-extension-kaito)

## 🎯 Overview

Deploy and manage AI models on AKS using **KAITO** and **Headlamp**.

### Key Components
- **KAITO**: Kubernetes AI Toolchain Operator - automates AI/ML model deployment
- **Headlamp**: Kubernetes GUI dashboard with KAITO plugin
- **Azure Monitor**: Prometheus metrics and Grafana dashboards

---

## � Why KAITO? Benefits

### Key Benefits

| Benefit | Description |
|---------|-------------|
| **Simplified Deployment** | Deploy AI models with a single YAML manifest instead of complex multi-step processes |
| **Automatic GPU Provisioning** | KAITO automatically provisions GPU nodes when you deploy a workspace |
| **Pre-configured Models** | 50+ popular models (Llama, Phi, Mistral, Falcon) ready to deploy with optimized settings |
| **Auto-scaling** | Scales GPU nodes based on workload demand |
| **Cost Optimization** | Nodes are only provisioned when needed, reducing idle GPU costs |
| **Kubernetes Native** | Works with existing K8s tools, RBAC, namespaces, and monitoring |
| **vLLM Integration** | Uses vLLM for high-performance inference with continuous batching |

### Business Value

- **⏱️ Time to Production**: Days → Hours
- **🧑‍💻 ML Expertise Required**: High → Low
- **💰 Infrastructure Cost**: Pay only for active workloads
- **🔧 Maintenance Overhead**: Minimal - KAITO handles updates and health checks

---

## ⚖️ KAITO vs Traditional Deployment

### Deployment Steps Comparison

| Step | Without KAITO | With KAITO |
|------|---------------|------------|
| **1. GPU Node Pool** | Manually create node pool with GPU SKU, taints, labels | ✅ Automatic - KAITO provisions on demand |
| **2. GPU Drivers** | Install NVIDIA drivers/device plugin manually | ✅ Automatic - Pre-configured in KAITO nodes |
| **3. Model Download** | Set up init container, PVC, download scripts | ✅ Automatic - KAITO handles model caching |
| **4. Inference Server** | Deploy vLLM/TGI manually, configure resources | ✅ Automatic - Optimized vLLM pre-configured |
| **5. Service/Ingress** | Create Service, configure networking | ✅ Automatic - Service created by KAITO |
| **6. Health Checks** | Configure liveness/readiness probes | ✅ Automatic - Built-in health monitoring |
| **7. Scaling** | Set up HPA, configure GPU metrics | ✅ Automatic - Node auto-provisioning |
| **Total YAML Lines** | ~300-500 lines across multiple files | **~20 lines in one file** |

### Without KAITO (Traditional Approach)

```bash
# Step 1: Create GPU node pool (~5 min)
az aks nodepool add \
  --resource-group $RG_NAME \
  --cluster-name $AKS_NAME \
  --name gpupool \
  --node-count 1 \
  --node-vm-size Standard_NV36ads_A10_v5 \
  --node-taints sku=gpu:NoSchedule \
  --labels sku=gpu

# Step 2: Install NVIDIA device plugin (~2 min)
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.1/nvidia-device-plugin.yml

# Step 3: Create PVC for model storage (~1 min)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: model-storage
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Gi
EOF

# Step 4: Download model (~10-30 min depending on model size)
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: download-model
spec:
  template:
    spec:
      containers:
      - name: download
        image: python:3.11
        command: ["pip", "install", "huggingface_hub", "&&", "huggingface-cli", "download", "microsoft/phi-4-mini-instruct"]
        volumeMounts:
        - name: model
          mountPath: /models
      volumes:
      - name: model
        persistentVolumeClaim:
          claimName: model-storage
      restartPolicy: Never
EOF

# Step 5: Deploy vLLM inference server (~5 min)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phi4-vllm
spec:
  replicas: 1
  selector:
    matchLabels:
      app: phi4-vllm
  template:
    metadata:
      labels:
        app: phi4-vllm
    spec:
      nodeSelector:
        sku: gpu
      tolerations:
      - key: sku
        value: gpu
        effect: NoSchedule
      containers:
      - name: vllm
        image: vllm/vllm-openai:latest
        args:
        - --model=/models/phi-4-mini-instruct
        - --gpu-memory-utilization=0.85
        - --max-model-len=65536
        resources:
          limits:
            nvidia.com/gpu: 1
        ports:
        - containerPort: 8000
        volumeMounts:
        - name: model
          mountPath: /models
      volumes:
      - name: model
        persistentVolumeClaim:
          claimName: model-storage
---
apiVersion: v1
kind: Service
metadata:
  name: phi4-vllm
spec:
  selector:
    app: phi4-vllm
  ports:
  - port: 80
    targetPort: 8000
EOF
```

**Total: ~150 lines of YAML, 5+ commands, 30-45 minutes**

### With KAITO (Simplified)

```yaml
# workspace-phi4.yaml - That's it! Just 15 lines!
apiVersion: kaito.sh/v1beta1
kind: Workspace
metadata:
  name: workspace-phi-4-mini-instruct
  namespace: default
resource:
  instanceType: "Standard_NV36ads_A10_v5"
  labelSelector:
    matchLabels:
      apps: phi-4-mini-instruct
inference:
  preset:
    name: phi-4-mini-instruct
```

```bash
# One command to deploy
kubectl apply -f workspace-phi4.yaml
```

**Total: 15 lines of YAML, 1 command, 10-15 minutes**

---

### ✅ Benefit of KAITO

| Category | Advantage |
|----------|-----------|
| **Simplicity** | Deploy complex AI models with minimal YAML |
| **Speed** | 3x faster deployment compared to manual setup |
| **Reliability** | Pre-tested configurations for each model |
| **Cost Efficiency** | GPU nodes auto-deprovision when workspace is deleted |
| **Model Catalog** | 50+ models with optimized presets (Llama, Phi, Mistral, etc.) |
| **Kubernetes Native** | Uses CRDs, integrates with existing K8s workflows |
| **Headlamp Integration** | GUI for non-CLI users, chat interface for testing |
| **Observability** | Built-in Prometheus metrics for vLLM |
| **Fine-tuning Support** | Supports LoRA adapters for model customization |
| **Multi-GPU** | Automatic tensor parallelism for large models |

---

## �📋 Prerequisites

### Tools Required
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)
- [Headlamp](https://headlamp.dev/)
- [Visual Studio Code](https://code.visualstudio.com/) with AKS extension

### Azure Requirements
- Azure subscription with **Owner** permissions
- GPU quota for one of the [KAITO supported SKUs](#-kaito-supported-gpu-skus)

---

## 🖥️ KAITO Supported GPU SKUs

> **Reference**: [KAITO Azure SKU Handler](https://github.com/kaito-project/kaito/blob/main/pkg/sku/azure_sku_handler.go)

KAITO only supports specific GPU VM sizes. Using unsupported SKUs will result in:
```
GPU config is nil for instance type <SKU>
```

### ✅ Supported SKUs

| SKU | GPU | Count | VRAM | Notes |
|-----|-----|-------|------|-------|
| **NVIDIA V100** |
| Standard_NC6s_v3 | V100 | 1 | 16 GB | |
| Standard_NC12s_v3 | V100 | 2 | 32 GB | |
| Standard_NC24s_v3 | V100 | 4 | 64 GB | |
| Standard_NC24rs_v3 | V100 | 4 | 64 GB | |
| **NVIDIA T4** |
| Standard_NC4as_T4_v3 | T4 | 1 | 16 GB | Budget-friendly |
| Standard_NC8as_T4_v3 | T4 | 1 | 16 GB | |
| Standard_NC16as_T4_v3 | T4 | 1 | 16 GB | |
| Standard_NC64as_T4_v3 | T4 | 4 | 64 GB | |
| **NVIDIA A10** |
| Standard_NV36ads_A10_v5 | A10 | 1 | 24 GB | ⭐ Recommended |
| Standard_NV72ads_A10_v5 | A10 | 2 | 48 GB | |
| **NVIDIA A100** |
| Standard_NC24ads_A100_v4 | A100 | 1 | 80 GB | NVMe enabled |
| Standard_NC48ads_A100_v4 | A100 | 2 | 160 GB | NVMe enabled |
| Standard_NC96ads_A100_v4 | A100 | 4 | 320 GB | NVMe enabled |
| Standard_ND96asr_A100_v4 | A100 | 8 | 320 GB | |
| Standard_ND96amsr_A100_v4 | A100 | 8 | 640 GB | NVMe enabled |
| **NVIDIA H100** |
| Standard_NC40ads_H100_v5 | H100 | 1 | 94 GB | NVMe enabled |
| Standard_NC80adis_H100_v5 | H100 | 2 | 188 GB | NVMe enabled |
| Standard_ND96isr_H100_v5 | H100 | 8 | 640 GB | NVMe enabled |
| Standard_NCC40ads_H100_v5 | H100 | 1 | 94 GB | |
| **NVIDIA H200** |
| Standard_ND96isr_H200_v5 | H200 | 8 | 1128 GB | NVMe enabled |
| **AMD Radeon** |
| Standard_NG32ads_V620_v1 | V620 | 1 | 32 GB | |
| Standard_NG32adms_V620_v1 | V620 | 1 | 32 GB | |
| Standard_NV32as_v4 | MI25 | 1 | 16 GB | |
| **NVIDIA M60 (Legacy)** |
| Standard_NV6 | M60 | 1 | 8 GB | |
| Standard_NV12 | M60 | 2 | 16 GB | |
| Standard_NV24 | M60 | 4 | 32 GB | |
| Standard_NV12s_v3 | M60 | 1 | 8 GB | |
| Standard_NV24s_v3 | M60 | 2 | 16 GB | |
| Standard_NV48s_v3 | M60 | 4 | 32 GB | |

### ❌ NOT Supported (Common Mistakes)

| SKU | Why Not Supported |
|-----|-------------------|
| Standard_NV6ads_A10_v5 | Not in KAITO config |
| Standard_NV12ads_A10_v5 | Not in KAITO config |
| Standard_NV18ads_A10_v5 | Not in KAITO config |
| Standard_NV36adms_A10_v5 | Not in KAITO config |

> **Tip**: For A10 GPUs, use `Standard_NV36ads_A10_v5` or `Standard_NV72ads_A10_v5`

---

## 🚀 Quick Start

### Step 1: Azure Login
```bash
az login --use-device-code
az extension add --name aks-preview --upgrade
```

### Step 2: Set Variables
```bash
export RAND=$RANDOM
export LOCATION=eastus
export RG_NAME=rg-kaito-demo-$RAND
export AKS_NAME=aks-kaito-$RAND

echo "Resource Group: $RG_NAME"
echo "AKS Cluster: $AKS_NAME"
```

### Step 3: Create Resource Group
```bash
az group create --name $RG_NAME --location $LOCATION
```

### Step 4: Create AKS Cluster with KAITO
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

### Step 5: Get Credentials
```bash
az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME --overwrite-existing
```

### Step 6: Verify KAITO Installation
```bash
kubectl get pods -n kube-system | grep kaito
```

### Step 7: Enable Azure Monitor (Prometheus + Grafana)
```bash
# Create Azure Monitor Workspace
az monitor account create \
  --name amw-kaito-$RAND \
  --resource-group $RG_NAME \
  --location $LOCATION

# Create Grafana
az grafana create \
  --name grafana-kaito-$RAND \
  --resource-group $RG_NAME \
  --location $LOCATION

# Get resource IDs
MONITOR_ID=$(az monitor account show --name amw-kaito-$RAND --resource-group $RG_NAME --query id -o tsv)
GRAFANA_ID=$(az grafana show --name grafana-kaito-$RAND --resource-group $RG_NAME --query id -o tsv)

# Enable monitoring on AKS
az aks update \
  --name $AKS_NAME \
  --resource-group $RG_NAME \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id $MONITOR_ID \
  --grafana-resource-id $GRAFANA_ID
```

---

## 🖥️ Headlamp Setup

### Install Headlamp
1. Download from https://headlamp.dev/
2. Install and open Headlamp

### Install KAITO Plugin
1. Click **Plugin Catalog**
2. Search for **Headlamp Kaito**
3. Click **Install** → **Reload now**

### Connect to Cluster
1. Headlamp auto-detects clusters from kubeconfig
2. Click your AKS cluster to connect

---

## 🤖 Deploy AI Model

### Via Headlamp (Recommended)
1. Click **KAITO** menu (bottom left)
2. Click **Model Catalog**
3. Find **Phi-4-Mini-Instruct** → Click **Deploy**
4. **IMPORTANT**: Edit the YAML to change instanceType:
   ```yaml
   spec:
     resource:
       instanceType: "Standard_NV12ads_A10_v5"
   ```
5. Click **Apply**
6. Monitor in **Kaito Workspaces** (~15 min)

### Via kubectl
```bash
kubectl apply -f workspace-phi4.yaml
```

---

## 🦙 Deploy Other LLMs

### Available Model Presets

| Model Family | Preset Name | Size | Auth Required |
|--------------|-------------|------|---------------|
| **Phi** | `phi-4-mini-instruct` | 3.8B | ❌ No |
| **Phi** | `phi-4` | 14B | ❌ No |
| **Llama 3.1** | `llama-3.1-8b-instruct` | 8B | ✅ Yes |
| **Llama 3.3** | `llama-3.3-70b-instruct` | 70B | ✅ Yes |
| **Mistral** | `mistral-7b-instruct` | 7B | ❌ No |
| **Falcon** | `falcon-7b-instruct` | 7B | ❌ No |
| **Qwen** | `qwen2.5-7b-instruct` | 7B | ❌ No |
| **DeepSeek** | `deepseek-r1-distill-llama-8b` | 8B | ❌ No |
| **Gemma** | `gemma-3-12b-instruct` | 12B | ✅ Yes |

> **Full list**: See [KAITO Supported Models](https://github.com/kaito-project/kaito/blob/main/presets/workspace/models/supported_models.yaml)

### Example: Deploy Llama 3.1 8B (Gated Model)

Llama models require HuggingFace authentication:

**Step 1: Accept License**
1. Go to https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct
2. Accept Meta's license agreement

**Step 2: Create HuggingFace Token**
1. Go to https://huggingface.co/settings/tokens
2. Create a token with `read` permissions

**Step 3: Create Kubernetes Secret**
```bash
kubectl create secret generic hf-token --from-literal=HF_TOKEN=hf_xxxxxxxxxxxxx
```

**Step 4: Create Workspace (workspace-llama31.yaml)**
```yaml
apiVersion: kaito.sh/v1beta1
kind: Workspace
metadata:
  name: workspace-llama-3-1-8b-instruct
resource:
  instanceType: "Standard_NV36ads_A10_v5"
  labelSelector:
    matchLabels:
      apps: llama-3-1-8b-instruct
inference:
  preset:
    name: llama-3.1-8b-instruct
    accessMode: private
    presetOptions:
      modelAccessSecret: hf-token
```

**Step 5: Deploy**
```bash
kubectl apply -f workspace-llama31.yaml
kubectl get workspace -w
```

### Example: Deploy Mistral 7B (Public Model)

Public models don't require authentication:

```yaml
# workspace-mistral.yaml
apiVersion: kaito.sh/v1beta1
kind: Workspace
metadata:
  name: workspace-mistral-7b-instruct
resource:
  instanceType: "Standard_NV36ads_A10_v5"
  labelSelector:
    matchLabels:
      apps: mistral-7b-instruct
inference:
  preset:
    name: mistral-7b-instruct
```

```bash
kubectl apply -f workspace-mistral.yaml
```

### Example: Deploy DeepSeek R1 (Reasoning Model)

```yaml
# workspace-deepseek.yaml
apiVersion: kaito.sh/v1beta1
kind: Workspace
metadata:
  name: workspace-deepseek-r1
resource:
  instanceType: "Standard_NV36ads_A10_v5"
  labelSelector:
    matchLabels:
      apps: deepseek-r1
inference:
  preset:
    name: deepseek-r1-distill-llama-8b
```

### GPU Requirements by Model Size

| Model Size | Recommended GPU | SKU Example |
|------------|-----------------|-------------|
| 3-8B | 1x A10 (24GB) | `Standard_NV36ads_A10_v5` |
| 12-14B | 1x A10 (24GB) | `Standard_NV36ads_A10_v5` |
| 70B | 2x A100 (160GB) | `Standard_NC48ads_A100_v4` |
| 70B+ | 4x A100 (320GB) | `Standard_NC96ads_A100_v4` |

---

## 💬 Test the Model

### Via Headlamp Chat
1. Click **Chat** in KAITO menu
2. Select workspace and model
3. Click **Go**
4. Enter prompts and test

### Via Port-Forward + REST
```bash
kubectl port-forward svc/workspace-phi-4-mini-instruct 8080:80
```

Then use test.http file with REST Client extension.

---

## 📊 Setup Monitoring

### Label the Service
```bash
kubectl label svc workspace-phi-4-mini-instruct kaito.sh/workspace=workspace-phi-4-mini-instruct
```

### Create ServiceMonitor
```bash
kubectl apply -f servicemonitor.yaml
```

### View in Grafana
1. Go to Azure Portal → your Grafana instance
2. Import vLLM dashboard from https://docs.vllm.ai

---

## 🔍 Troubleshooting & Investigation

### Check Workspace Status

```bash
# Quick status check
kubectl get workspace

# Detailed status with conditions
kubectl describe workspace <workspace-name>

# Watch for status changes
kubectl get workspace -w
```

**Status Columns Explained:**

| Column | Meaning |
|--------|---------|
| `RESOURCEREADY` | GPU node is provisioned and ready |
| `INFERENCEREADY` | Model is loaded and serving requests |
| `WORKSPACESUCCEEDED` | Everything is healthy |

### Check Pod Status

```bash
# List all pods
kubectl get pods

# Get pod details
kubectl describe pod <pod-name>

# Check pod events
kubectl get events --sort-by='.lastTimestamp' | grep <workspace-name>
```

**Common Pod States:**

| State | Meaning | Action |
|-------|---------|--------|
| `Pending` | Waiting for GPU node | Wait 5-10 min for node provisioning |
| `ContainerCreating` | Pulling container image | Wait 1-2 min |
| `Init:0/1` | Init container downloading model | Wait 2-5 min |
| `Running 0/1` | Model loading into GPU | Wait 2-5 min |
| `Running 1/1` | ✅ Ready to serve | Test the endpoint |
| `CrashLoopBackOff` | Container crashing | Check logs for errors |
| `OOMKilled` | Out of memory | Use larger GPU or reduce model size |

### Check Logs

```bash
# View main container logs
kubectl logs <pod-name> --tail=50

# View init container logs (model download)
kubectl logs <pod-name> -c model-weights-downloader

# Follow logs in real-time
kubectl logs <pod-name> -f

# View all container logs
kubectl logs <pod-name> --all-containers
```

### Common Issues & Solutions

#### Issue: "GPU config is nil for instance type"

```
GPU config is nil for instance type Standard_NV12ads_A10_v5
```

**Cause:** Using unsupported GPU SKU.

**Solution:** Use a [supported SKU](#-kaito-supported-gpu-skus). For A10, use `Standard_NV36ads_A10_v5` or `Standard_NV72ads_A10_v5`.

---

#### Issue: "Unsupported inference preset name"

```
validation failed: invalid value: Unsupported inference preset name llama3.1-8b-instruct
```

**Cause:** Incorrect preset name format.

**Solution:** Check exact preset names in [supported_models.yaml](https://github.com/kaito-project/kaito/blob/main/presets/workspace/models/supported_models.yaml). Use dots and dashes correctly: `llama-3.1-8b-instruct`

---

#### Issue: "unknown field in spec"

```
unknown field "spec" in kaito.sh/v1beta1.Workspace
```

**Cause:** Using wrong YAML structure (v1alpha1 style).

**Solution:** KAITO v1beta1 uses root-level fields, not wrapped in `spec`:

```yaml
# ❌ Wrong (v1alpha1 style)
spec:
  resource:
    instanceType: "..."

# ✅ Correct (v1beta1 style)
resource:
  instanceType: "..."
```

---

#### Issue: "401 Unauthorized" for gated models

```
401 Client Error: Unauthorized for model meta-llama/Llama-3.1-8B-Instruct
```

**Cause:** Missing or invalid HuggingFace token for gated model.

**Solution:**
1. Accept model license on HuggingFace
2. Create secret: `kubectl create secret generic hf-token --from-literal=HF_TOKEN=hf_xxx`
3. Add to workspace:
   ```yaml
   inference:
     preset:
       name: llama-3.1-8b-instruct
       accessMode: private
       presetOptions:
         modelAccessSecret: hf-token
   ```

---

#### Issue: "CUDA out of memory"

```
torch.cuda.OutOfMemoryError: CUDA out of memory
```

**Cause:** Model too large for GPU memory.

**Solution:** 
1. Use larger GPU SKU
2. Create ConfigMap to reduce context length:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: model-config
   data:
     inference_config.yaml: |
       vllm:
         gpu-memory-utilization: 0.85
         max-model-len: 32768
   ```
3. Reference in workspace: `inference.config: model-config`

---

#### Issue: Pod stuck in "Pending"

**Cause:** No GPU nodes available or quota issues.

**Solution:**
```bash
# Check node status
kubectl get nodes

# Check KAITO node claims
kubectl get nodeclaims

# Check for quota errors
kubectl describe nodeclaim <nodeclaim-name>
```

If quota issue, request GPU quota increase in Azure Portal.

---

### Useful Investigation Commands

```bash
# Check KAITO controller logs
kubectl logs -n kube-system -l app=kaito-workspace --tail=100

# Check GPU node status
kubectl get nodes -l kaito.sh/workspace=<workspace-name>

# Check node GPU resources
kubectl describe node <gpu-node-name> | grep -A5 "Allocatable:"

# Check service endpoints
kubectl get svc | grep workspace
kubectl get endpoints | grep workspace

# Test inference endpoint manually
kubectl port-forward svc/<workspace-name> 8080:80
curl http://localhost:8080/v1/models
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"<model-name>","messages":[{"role":"user","content":"Hi"}]}'

# Check vLLM metrics
curl http://localhost:8080/metrics | grep vllm
```

### Workspace Field Reference

```bash
# Get all workspace fields
kubectl explain workspace --recursive

# Get specific field info
kubectl explain workspace.inference.preset
kubectl explain workspace.resource
```

---

## 🧹 Cleanup
```bash
az group delete --name $RG_NAME --yes --no-wait
```

---

## 📂 Files

| File | Description |
|------|-------------|
| `demokaitoheadlamp.sh` | Automation script |
| `workspace-phi4.yaml` | KAITO workspace manifest |
| `servicemonitor.yaml` | Prometheus ServiceMonitor |
| `test.http` | REST Client test file |

---

## ⏱️ Timeline

| Step | Time |
|------|------|
| Create AKS + KAITO | 10 min |
| Enable Monitoring | 5 min |
| Setup Headlamp | 3 min |
| Deploy Model | 15 min |
| Test & Demo | 10 min |

**Total: ~45 minutes**

---

## 📚 References

| Resource | Link |
|----------|------|
| **KAITO for AKS (Official)** | https://learn.microsoft.com/en-us/azure/aks/aks-extension-kaito |
| **KAITO GitHub** | https://github.com/kaito-project/kaito |
| **Supported Models** | https://github.com/kaito-project/kaito/blob/main/presets/workspace/models/supported_models.yaml |
| **Headlamp** | https://headlamp.dev/ |
| **Headlamp KAITO Plugin** | https://github.com/headlamp-k8s/plugins/tree/main/kaito |
| **vLLM Documentation** | https://docs.vllm.ai/ |
| **AKS AI Workloads Lab** | https://azure-samples.github.io/aks-labs/docs/ai-workloads-on-aks/ |
