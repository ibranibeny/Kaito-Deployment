# KAITO Multi-Node Deployment with llm-d Distribution Layer

> Deploy **gpt-oss-20b** on AKS with **3x NVIDIA A10 GPUs** in **Indonesia Central** region, with **llm-d** for Prefill/Decode disaggregation

## Quick Summary

| Parameter | Value |
|-----------|-------|
| **Region** | Indonesia Central |
| **GPU VM SKU** | Standard_NV12ads_A10_v5 |
| **GPU Type** | NVIDIA A10 (1/3 fractional, 8GB) |
| **Node Count** | 3 nodes |
| **Total GPU Memory** | 24GB (3 x 8GB) |
| **Model** | gpt-oss-20b |
| **Distribution Layer** | llm-d (Prefill/Decode Disaggregation) |
| **UI** | Streamlit Chat Interface |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                   AKS Cluster - Indonesia Central                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                    ┌─────────────────────────────────┐                       │
│                    │   llm-d Inference Gateway       │                       │
│                    │   ├─ Prefix-cache aware routing │                       │
│                    │   ├─ Load balancing             │                       │
│                    │   └─ P/D phase splitting        │                       │
│                    └───────────────┬─────────────────┘                       │
│                                    │                                         │
│              ┌─────────────────────┼─────────────────────┐                   │
│              │                     │                     │                   │
│              ▼                     ▼                     ▼                   │
│   ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│   │     Node 1       │  │     Node 2       │  │     Node 3       │          │
│   │ ╔══════════════╗ │  │ ╔══════════════╗ │  │ ╔══════════════╗ │          │
│   │ ║ A10 8GB GPU  ║ │  │ ║ A10 8GB GPU  ║ │  │ ║ A10 8GB GPU  ║ │          │
│   │ ║  vLLM Pod    ║ │  │ ║  vLLM Pod    ║ │  │ ║  vLLM Pod    ║ │          │
│   │ ║  (Prefill)   ║ │  │ ║  (Decode)    ║ │  │ ║  (Decode)    ║ │          │
│   │ ╚══════════════╝ │  │ ╚══════════════╝ │  │ ╚══════════════╝ │          │
│   └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘          │
│            │                     │                     │                    │
│            └─────────────────────┼─────────────────────┘                    │
│                                  │                                          │
│                       ┌──────────┴──────────┐                               │
│                       │  NIXL KV Transfer   │                               │
│                       │  (GPU-to-GPU)       │                               │
│                       └─────────────────────┘                               │
│                                                                              │
│         + KAITO Controller + CoreDNS + System Components                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## What is llm-d?

**llm-d** is a Kubernetes-native distributed inference layer that enhances LLM serving with intelligent request routing and Prefill/Decode disaggregation.

### Key Features

| Feature | Description | Benefit |
|---------|-------------|---------|
| **Prefill/Decode Disaggregation** | Separates prompt processing (Prefill) from token generation (Decode) | Reduces Time-to-First-Token (TTFT) |
| **Inference Gateway** | Envoy-based routing with intelligent scheduling | Cache-aware, load-aware routing |
| **NIXL KV Cache Transfer** | GPU-to-GPU direct cache transfer | Efficient sharding without CPU bottleneck |
| **Kubernetes Native** | CRDs (InferencePool, InferenceModel) | Native HPA, Prometheus metrics |

### Prefill vs Decode

```
┌─────────────────────────────────────────────────────────────────┐
│                    LLM Inference Phases                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  PREFILL PHASE (Compute-Intensive)                               │
│  ├─ Process entire input prompt                                  │
│  ├─ Compute attention for all tokens                             │
│  ├─ Build KV cache                                               │
│  └─ Suitable for: High-compute GPUs                              │
│                                                                  │
│  DECODE PHASE (Memory-Bound)                                     │
│  ├─ Generate tokens one-by-one                                   │
│  ├─ Read from KV cache                                           │
│  ├─ Lower compute, higher memory bandwidth                       │
│  └─ Suitable for: High-bandwidth GPUs                            │
│                                                                  │
│  llm-d BENEFIT:                                                  │
│  ├─ Route Prefill to dedicated nodes                             │
│  ├─ Route Decode to multiple nodes                               │
│  └─ Transfer KV cache via NIXL                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## GPU Specifications

### Standard_NV12ads_A10_v5

| Component | Specification |
|-----------|---------------|
| **vCPUs** | 12 |
| **RAM** | 110 GiB |
| **GPU** | 1x NVIDIA A10 |
| **GPU Memory** | 8GB GDDR6 (1/3 of A10) |
| **Architecture** | Ampere (GA102) |
| **FP16 Performance** | 31.2 TFLOPS |
| **Temp Storage** | 360 GiB SSD |
| **Network** | 20 Gbps |

### Why 3 Nodes?

```
gpt-oss-20b Requirements:
├── Model Weights: 12.9 GiB
├── KV Cache:      ~2-4 GiB (dynamic)
├── Activations:   ~1-2 GiB
└── CUDA Overhead: ~0.5 GiB
    ────────────────────────
    Total: ~16-20 GiB per inference

With 3x fractional A10 (24GB total):
├── Node 1: Serves requests (Leader)
├── Node 2: High availability
└── Node 3: Load balancing
```

---

## Prerequisites

- Azure subscription with GPU quota
- Azure CLI with aks-preview extension
- kubectl
- Python 3.8+ with streamlit

```bash
# Check GPU quota in Indonesia Central
az vm list-usage --location indonesiacentral \
    --query "[?contains(name.value, 'NV')]" -o table
```

---

## Quick Start

### Interactive Deployment

```bash
# Run the deployment script
./multinodedemokaito.sh

# Use menu:
#   1) Azure Login
#   2) Set Variables
#   3) Create Resource Group
#   4) Create AKS with GPU Nodes
#   5) Get Credentials
#   6) Create Workspace YAML
#   7) Deploy KAITO Workspace
#   8) Deploy llm-d Distribution Layer  ← NEW!
#   9) Monitor Status
#  10) Streamlit Chat UI
#  11) CLI Test
#  12) Cleanup
#
#   a) Run ALL (1-8)
#   q) Quit
```

### Manual Deployment

```bash
# Variables
export LOCATION="indonesiacentral"
export RG_NAME="rg-kaito-multinode-$RANDOM"
export AKS_NAME="aks-kaito-mn"

# Create resource group
az group create --name $RG_NAME --location $LOCATION

# Create AKS (10-15 minutes)
az aks create \
    --resource-group $RG_NAME \
    --name $AKS_NAME \
    --location $LOCATION \
    --node-count 3 \
    --node-vm-size Standard_NV12ads_A10_v5 \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --enable-managed-identity \
    --enable-oidc-issuer \
    --enable-ai-toolchain-operator \
    --generate-ssh-keys

# Get credentials
az aks get-credentials --resource-group $RG_NAME --name $AKS_NAME

# Deploy workspace
kubectl apply -f workspace-gpt-oss-20b-multinode.yaml
```

### Deploy llm-d Distribution Layer

```bash
# Add llm-d Helm repo
helm repo add llm-d https://llm-d.github.io/llm-d/
helm repo update

# Install llm-d operator
helm upgrade --install llm-d-operator llm-d/llm-d-operator \
    --namespace llm-d \
    --create-namespace

# Apply llm-d configurations (generated by script)
kubectl apply -f llmd-inference-pool.yaml
kubectl apply -f llmd-inference-model.yaml
kubectl apply -f llmd-gateway.yaml
```

---

## llm-d Configuration

### InferencePool (llmd-inference-pool.yaml)

```yaml
apiVersion: inference.networking.x-k8s.io/v1alpha2
kind: InferencePool
metadata:
  name: kaito-gpt-oss-20b-pool
spec:
  targetRef:
    kind: Service
    name: workspace-gpt-oss-20b
  scheduling:
    prefixCacheAware: true
    loadBalancing: least-loaded
```

### InferenceModel (llmd-inference-model.yaml)

```yaml
apiVersion: inference.networking.x-k8s.io/v1alpha2
kind: InferenceModel
metadata:
  name: gpt-oss-20b
spec:
  modelName: "gpt-oss-20b"
  poolRef:
    name: kaito-gpt-oss-20b-pool
  criticality: Standard
```

### Gateway (llmd-gateway.yaml)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: llmd-inference-gateway
spec:
  gatewayClassName: llm-d
  listeners:
  - name: http
    port: 8080
    protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: llmd-model-route
spec:
  parentRefs:
  - name: llmd-inference-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v1
    backendRefs:
    - group: inference.networking.x-k8s.io
      kind: InferencePool
      name: kaito-gpt-oss-20b-pool
```

---

## Streamlit UI

The Streamlit app provides an interactive chat interface with inference parameter controls.

### Features

| Feature | Description |
|---------|-------------|
| **Temperature** | Controls randomness (0.0 - 2.0) |
| **Top-P** | Nucleus sampling threshold (0.0 - 1.0) |
| **Top-K** | Limit vocabulary selection (1 - 100) |
| **Max Tokens** | Maximum response length |
| **Tokens/sec** | Real-time generation speed |
| **Model Display** | Shows active model name |

### Running Streamlit

```bash
# Terminal 1: Port forward KAITO service
kubectl port-forward svc/workspace-gpt-oss-20b 8080:80

# Terminal 2: Start Streamlit
pip install streamlit requests
streamlit run streamlit_app.py

# Open browser: http://localhost:8501
```

### Screenshot Preview

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 🤖 KAITO Chat                                                [sidebar] │
├─────────────────────────────────────────────────────────────────────────┤
│                                           │  📊 Model Info             │
│  User: What is machine learning?          │  ├─ Model: gpt-oss-20b     │
│  ─────────────────────────────────────    │  └─ Status: Connected      │
│  Assistant: Machine learning is a         │                            │
│  subset of artificial intelligence...     │  ⚙️ Parameters             │
│                                           │  ├─ Temperature: 0.7       │
│  ⏱️ 1.2s | 45.3 tokens/sec               │  ├─ Top-P: 0.9             │
│                                           │  ├─ Top-K: 50              │
│                                           │  └─ Max Tokens: 512        │
│  ────────────────────────────────────     │                            │
│  [Type your message...]            [Send] │  [Clear Chat]              │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Workspace YAML

The script generates this workspace configuration:

> **Important**: KAITO Workspace CRD does NOT use `spec:` - the `resource` and `inference` fields are top-level.

```yaml
apiVersion: kaito.sh/v1beta1
kind: Workspace
metadata:
  name: workspace-gpt-oss-20b
  labels:
    app: gpt-oss-20b
resource:
  count: 3
  instanceType: "Standard_NV12ads_A10_v5"
  labelSelector:
    matchLabels:
      apps: gpt-oss-20b
inference:
  preset:
    name: "gpt-oss-20b"
```

> **Note**: `gpt-oss-20b` is a public model and does NOT require HF_TOKEN authentication. For gated models like Llama or Gemma, add `presetOptions.modelAccessSecret`.

---

## Monitoring

### Check Workspace Status

```bash
# Workspace status
kubectl get workspace workspace-gpt-oss-20b -o wide

# Conditions
kubectl get workspace workspace-gpt-oss-20b \
    -o jsonpath='{range .status.conditions[*]}{.type}: {.status}{"\n"}{end}'

# Pods
kubectl get pods -l apps=gpt-oss-20b -o wide

# llm-d components
kubectl get inferencepool,inferencemodel,gateway
```

### Expected Status Flow

```
1. ResourceReady: Pending → True    (Nodes provisioned)
2. ModelConfigReady: True           (Model config loaded)
3. InferenceReady: Pending → True   (Model downloaded & serving)
```

---

## Testing

### CLI Test

```bash
# Port forward
kubectl port-forward svc/workspace-gpt-oss-20b 8080:80 &

# Health check
curl http://localhost:8080/health

# Chat completion
curl -X POST http://localhost:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "gpt-oss-20b",
        "messages": [{"role": "user", "content": "Hello!"}],
        "max_tokens": 100,
        "temperature": 0.7
    }'
```

---

## Cost Estimation

| Component | SKU | Qty | Price/hr | Monthly (730h) |
|-----------|-----|-----|----------|----------------|
| GPU Nodes | Standard_NV12ads_A10_v5 | 3 | ~$1.20 | ~$2,628 |
| **Total** | | | ~$3.60/hr | ~$2,628/mo |

> 💡 **Tip**: Use Azure Spot instances for dev/test to reduce costs by up to 90%

---

## Troubleshooting

### GPU Quota Issues

```bash
# Request quota increase for NV series in Indonesia Central
az quota update --resource-name "standardNVADSA10v5Family" \
    --scope "/subscriptions/YOUR-SUB-ID/providers/Microsoft.Compute/locations/indonesiacentral" \
    --limit-value 36 \
    --resource-type dedicated
```

### Pod Not Starting

```bash
# Check events
kubectl describe workspace workspace-gpt-oss-20b

# Check pod logs
kubectl logs -l apps=gpt-oss-20b -f
```

### Connection Issues

```bash
# Verify service exists
kubectl get svc workspace-gpt-oss-20b

# Test connectivity
kubectl run curl --image=curlimages/curl --rm -it -- \
    curl -s http://workspace-gpt-oss-20b/health
```

---

## Cleanup

```bash
# Delete everything
az group delete --name $RG_NAME --yes --no-wait

# Remove kubeconfig
rm ~/.kube/config-kaito-multinode-*
```

---

## Files

| File | Description |
|------|-------------|
| `multinodedemokaito.sh` | Main deployment script |
| `streamlit_app.py` | Chat UI application |
| `workspace-gpt-oss-20b-multinode.yaml` | KAITO workspace config |
| `llmd-inference-pool.yaml` | llm-d InferencePool config |
| `llmd-inference-model.yaml` | llm-d InferenceModel config |
| `llmd-gateway.yaml` | llm-d Gateway config |
| `multinode-demo-env.sh` | Environment variables |
| `test-multinode.sh` | Validation script |

---

## References

- [KAITO GitHub](https://github.com/kaito-project/kaito)
- [llm-d GitHub](https://github.com/llm-d/llm-d)
- [llm-d Documentation](https://llm-d.github.io/llm-d/)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [Azure NV-series VMs](https://learn.microsoft.com/azure/virtual-machines/nv-series)
- [Streamlit Documentation](https://docs.streamlit.io)
