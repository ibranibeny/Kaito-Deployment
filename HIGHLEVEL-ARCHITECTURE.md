# High-Level Architecture — KAITO + Llama 3 + RAG + PostgreSQL (pgvector)

> **VM SKU**: Standard_NC80adIS_H100_v5 (80 vCPUs, 8x NVIDIA H100 80GB NVL, 640GB GPU VRAM)
> **Model**: Meta Llama 3 (70B or 8B) via KAITO preset
> **Vector DB**: Azure Database for PostgreSQL Flexible Server with **pgvector** extension
> **Frontend**: Streamlit chat UI running as K8s Deployment
> **Network**: Hub-Spoke topology with Azure Firewall + Application Gateway (WAF v2)

---

## 1. Hub-and-Spoke Network Topology

```
                                ┌─────────────────────┐
                                │      INTERNET        │
                                └──────────┬──────────┘
                                           │
                                           │ HTTPS (443)
                                           ▼
┌──────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                      │
│                              HUB VNET  (10.0.0.0/16)                                                 │
│                                                                                                      │
│   ┌──────────────────────────────┐       ┌──────────────────────────────────────────────────────┐    │
│   │  Azure Application Gateway   │       │  Azure Firewall                                      │    │
│   │  (WAF v2)                    │       │  (AzureFirewallSubnet 10.0.1.0/26)                   │    │
│   │  AppGwSubnet 10.0.4.0/24    │       │                                                      │    │
│   │                              │       │  Egress Rules (FQDN):                                │    │
│   │  ┌────────────────────────┐  │       │  ├─ *.huggingface.co          (model download)       │    │
│   │  │ Listeners:             │  │       │  ├─ mcr.microsoft.com         (KAITO images)         │    │
│   │  │ ├─ :443 (HTTPS)       │  │       │  ├─ *.docker.io               (container images)     │    │
│   │  │ │  TLS cert (KV ref)  │  │       │  ├─ pypi.org                  (Python packages)      │    │
│   │  │ │                     │  │       │  ├─ *.blob.core.windows.net   (Azure Storage)        │    │
│   │  │ ├─ WAF Policy:        │  │       │  └─ *.postgres.database.azure.com (PostgreSQL)       │    │
│   │  │ │  OWASP 3.2 rules    │  │       │                                                      │    │
│   │  │ │  Bot protection     │  │       │  Network Rules:                                       │    │
│   │  │ │  Rate limiting      │  │       │  ├─ Allow AKS → PostgreSQL (5432)                     │    │
│   │  │ │  Geo-filtering      │  │       │  ├─ Allow AKS → Key Vault (443)                       │    │
│   │  │ │                     │  │       │  └─ Deny all other outbound                            │    │
│   │  │ └─ Backend Pool:      │  │       └──────────────────────────────────────────────────────┘    │
│   │  │    AKS Ingress LB IP  │  │                                                                   │
│   │  └────────────────────────┘  │       ┌───────────────────────┐  ┌─────────────────────────────┐  │
│   └──────────────────────────────┘       │  Azure Bastion        │  │  Azure Monitor              │  │
│              │                            │  (Admin SSH)          │  │  ├─ Log Analytics Workspace │  │
│              │ Backend: AKS Ingress       │  10.0.2.0/26          │  │  ├─ Prometheus (managed)    │  │
│              │ (Private IP in AKS VNet)   └───────────────────────┘  │  └─ Grafana (vLLM metrics)  │  │
│              │                                                       └─────────────────────────────┘  │
└──────────────┼───────────────────────────────────────────────────────────────────────────────────────┘
               │
       ┌───────┴──────── VNet Peering ──────────┬────────────────────────────────────┐
       │                                         │                                    │
       ▼                                         ▼                                    ▼
┌──────────────────────────────────┐  ┌──────────────────────────────┐  ┌─────────────────────────────┐
│  SPOKE 1: AKS VNET              │  │  SPOKE 2: DATA VNET          │  │  SPOKE 3: MGMT VNET         │
│  10.1.0.0/16                    │  │  10.2.0.0/16                 │  │  10.3.0.0/16                │
│                                  │  │                              │  │                             │
│  ┌────────────────────────────┐  │  │  ┌────────────────────────┐  │  │  ┌───────────────────────┐  │
│  │ AKS Cluster               │  │  │  │ Azure Database for     │  │  │  │ Key Vault             │  │
│  │ (KAITO-enabled)           │  │  │  │ PostgreSQL Flex        │  │  │  │ (Secrets, HF Token,   │  │
│  │                           │  │  │  │ ┌────────────────────┐ │  │  │  │  TLS Certs)           │  │
│  │ System Pool: 3x D4s_v5   │  │  │  │ │ pgvector extension │ │  │  │  └───────────────────────┘  │
│  │ GPU Pool: 1x NC80adIS    │  │  │  │ │ ──────────────────  │ │  │  │                             │
│  │   _H100_v5               │  │  │  │ │ Vector dimensions:  │ │  │  │  ┌───────────────────────┐  │
│  │   (8x H100, 640GB VRAM)  │  │  │  │ │ 4096 (llama3-70B)  │ │  │  │  │ ACR (Private)         │  │
│  │                           │  │  │  │ │ or 384 (bge-small) │ │  │  │  │ KAITO + App images    │  │
│  │ UDR → Azure Firewall     │  │  │  │ │                    │ │  │  │  └───────────────────────┘  │
│  │ (all egress through Hub)  │  │  │  │ │ Tables:            │ │  │  │                             │
│  └────────────────────────────┘  │  │  │ │ ├─ embeddings     │ │  │  │  ┌───────────────────────┐  │
│                                  │  │  │ │ ├─ documents      │ │  │  │  │ Azure DNS Private     │  │
│  Private Endpoint:               │  │  │ │ └─ chat_history   │ │  │  │  │ Resolver              │  │
│  ├─ ACR (pull images)           │  │  │ │                    │ │  │  │  └───────────────────────┘  │
│  ├─ Key Vault (secrets)         │  │  │ └────────────────────┘ │  │  │                             │
│  └─ PostgreSQL (5432)           │  │  │                        │  │  │                             │
│                                  │  │  │ Private Endpoint:     │  │  │                             │
└──────────────────────────────────┘  │  │ 10.2.0.4 (port 5432) │  │  └─────────────────────────────┘
                                      │  │                        │  │
                                      │  │ Entra Auth + MI        │  │
                                      │  │ (passwordless)         │  │
                                      │  └────────────────────────┘  │
                                      └──────────────────────────────┘
```

---

## 2. AKS — Services and Deployments (K8s Resource View)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                        AKS CLUSTER — K8s Services & Deployments                                               │
│                        --enable-ai-toolchain-operator  --network-plugin azure --network-plugin-mode overlay   │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                               │
│  ┌── NAMESPACE: ingress-nginx ────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  Deployment: ingress-nginx-controller              Service: ingress-nginx-controller                   │  │
│  │  ├─ Replicas: 2                                    ├─ Type: LoadBalancer                                │  │
│  │  ├─ Image: registry.k8s.io/ingress-nginx           │  (Internal LB w/ Azure annotation)                │  │
│  │  │         /controller:v1.12.x                     ├─ Port: 80 (HTTP), 443 (HTTPS)                     │  │
│  │  └─ nodeSelector: agentpool=system                 └─ loadBalancerIP: 10.1.0.100                       │  │
│  │                                                       (← App Gateway backend points here)               │  │
│  │  ConfigMap: ingress-nginx-controller                                                                    │  │
│  │  ├─ proxy-body-size: "100m"    (allow large doc uploads)                                                │  │
│  │  └─ proxy-read-timeout: "300"  (long LLM inference requests)                                            │  │
│  │                                                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── NAMESPACE: app ──────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  ┌── Deployment: streamlit-frontend ──────────────────────────────────────────────────────────────┐    │  │
│  │  │  Replicas: 2   │  nodeSelector: agentpool=system                                                │    │  │
│  │  │                                                                                                  │    │  │
│  │  │  ┌── Pod: streamlit-frontend-xxxxx ──────────────────────────────────────────────────────────┐  │    │  │
│  │  │  │  container: streamlit                                                                      │  │    │  │
│  │  │  │  ├─ Image: <acr>.azurecr.io/streamlit-kaito:v1.0                                          │  │    │  │
│  │  │  │  ├─ Port: 8501                                                                             │  │    │  │
│  │  │  │  ├─ Env:                                                                                   │  │    │  │
│  │  │  │  │   KAITO_ENDPOINT=http://workspace-llama3.default.svc.cluster.local/v1/chat/completions  │  │    │  │
│  │  │  │  │   RAG_ENDPOINT=http://rag-llama3.default.svc.cluster.local/v1/chat/completions          │  │    │  │
│  │  │  │  │   PG_CONN_STRING=<from Secret: pg-credentials>                                          │  │    │  │
│  │  │  │  ├─ Resources: cpu=500m, memory=1Gi                                                        │  │    │  │
│  │  │  │  └─ Probes: readiness → GET /healthz :8501                                                 │  │    │  │
│  │  │  └────────────────────────────────────────────────────────────────────────────────────────────┘  │    │  │
│  │  └──────────────────────────────────────────────────────────────────────────────────────────────────┘    │  │
│  │                                                                                                        │  │
│  │  Service: streamlit-frontend                Ingress: streamlit-ingress                                  │  │
│  │  ├─ Type: ClusterIP                         ├─ ingressClassName: nginx                                  │  │
│  │  ├─ Port: 80 → 8501                         ├─ host: ai.contoso.com                                    │  │
│  │  └─ Selector: app=streamlit-frontend        ├─ path: / → svc/streamlit-frontend:80                     │  │
│  │                                              └─ tls: secret/tls-ai-contoso                              │  │
│  │                                                                                                        │  │
│  │  Secret: pg-credentials                     Secret: tls-ai-contoso                                     │  │
│  │  ├─ PG_HOST: <pg>.postgres.database...     ├─ tls.crt (from Key Vault via CSI)                         │  │
│  │  ├─ PG_DATABASE: ragdb                      └─ tls.key                                                  │  │
│  │  └─ PG_PASSWORD: <from Key Vault>                                                                      │  │
│  │                                                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── NAMESPACE: kaito-workspace ──────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  Deployment: kaito-workspace-controller     (installed via Helm: kaito/workspace)                      │  │
│  │  ├─ Replicas: 1                              Watches: Workspace CRDs                                   │  │
│  │  ├─ Image: mcr.microsoft.com/kaito/workspace-controller:v0.9.x                                        │  │
│  │  └─ ServiceAccount: kaito-workspace (w/ ClusterRole for Workspace, Machine, Deployment, Service CRUD) │  │
│  │                                                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── NAMESPACE: kaito-ragengine ──────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  Deployment: kaito-ragengine-controller     (installed via Helm: kaito/ragengine)                      │  │
│  │  ├─ Replicas: 1                              Watches: RAGEngine CRDs                                   │  │
│  │  ├─ Image: mcr.microsoft.com/kaito/ragengine-controller:v0.9.x                                        │  │
│  │  └─ ServiceAccount: kaito-ragengine (w/ ClusterRole for RAGEngine, Machine, Deployment, Service CRUD) │  │
│  │                                                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── NAMESPACE: gpu-provisioner ──────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  Deployment: gpu-provisioner                (Karpenter-based, provisions GPU VMs via Azure ARM)        │  │
│  │  ├─ Replicas: 1                                                                                        │  │
│  │  └─ Watches: Machine CRs → provisions Standard_NC80adIS_H100_v5 nodes                                 │  │
│  │                                                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── NAMESPACE: default ─── (Workloads created by KAITO controllers) ─────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  ┌── Workspace CRD ─────────────────────────┐  ┌── RAGEngine CRD ─────────────────────────────────┐   │  │
│  │  │  workspace/workspace-llama3               │  │  ragengine/rag-llama3                             │   │  │
│  │  │  → Deployment: workspace-llama3           │  │  → Deployment: rag-llama3                         │   │  │
│  │  │  → Service: workspace-llama3              │  │  → Service: rag-llama3                             │   │  │
│  │  │  → Machine CR → GPU Node (NC80)           │  │  → PVC: pvc-ragengine-vector-db                   │   │  │
│  │  └───────────────────────────────────────────┘  └──────────────────────────────────────────────────┘   │  │
│  │                                                                                                        │  │
│  │  (Details in Sections 3 & 4 below)                                                                     │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ── kubectl get all,workspace,ragengine,pvc,ingress -A (expected output) ──────────────────────────────────  │
│                                                                                                               │
│  NAMESPACE        NAME                                             READY   STATUS    AGE                      │
│  ingress-nginx    pod/ingress-nginx-controller-xxxxx-xxxxx         1/1     Running   12h                      │
│  app              pod/streamlit-frontend-xxxxx-xxxxx               1/1     Running   8h                       │
│  app              pod/streamlit-frontend-xxxxx-yyyyy               1/1     Running   8h                       │
│  kaito-workspace  pod/kaito-workspace-controller-xxxxx             1/1     Running   12h                      │
│  kaito-ragengine  pod/kaito-ragengine-controller-xxxxx             1/1     Running   12h                      │
│  gpu-provisioner  pod/gpu-provisioner-xxxxx                        1/1     Running   12h                      │
│  default          pod/workspace-llama3-xxxxx-xxxxx                 1/1     Running   6h                       │
│  default          pod/rag-llama3-xxxxx-xxxxx                       1/1     Running   5h                       │
│                                                                                                               │
│  NAMESPACE        NAME                                TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)     │
│  ingress-nginx    svc/ingress-nginx-controller        LoadBalancer   10.0.x.x      10.1.0.100    80,443      │
│  app              svc/streamlit-frontend              ClusterIP      10.0.x.x      <none>        80          │
│  default          svc/workspace-llama3                ClusterIP      10.0.x.x      <none>        80          │
│  default          svc/rag-llama3                      ClusterIP      10.0.x.x      <none>        80          │
│                                                                                                               │
│  NAMESPACE   NAME                               INSTANCE                  RESOURCEREADY  INFERENCEREADY      │
│  default     workspace/workspace-llama3         Standard_NC80adIS_H100    True           True                │
│                                                                                                               │
│  NAMESPACE   NAME                     STATUS   AGE                                                            │
│  default     ragengine/rag-llama3     Ready    5h                                                             │
│                                                                                                               │
│  NAMESPACE   NAME                          STATUS  CAPACITY  STORAGECLASS                                     │
│  default     pvc/pvc-ragengine-vector-db   Bound   50Gi      managed-csi-premium                              │
│                                                                                                               │
│  NAMESPACE   NAME                          CLASS   HOSTS             ADDRESS       PORTS                       │
│  app         ingress/streamlit-ingress     nginx   ai.contoso.com    10.1.0.100    80, 443                    │
│                                                                                                               │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. KAITO Workspace — Llama 3 on NC80 (8x H100)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                               │
│  KAITO Workspace CRD for Llama 3                         GPU Node: Standard_NC80adIS_H100_v5                  │
│  (auto-provisioned by GPU Provisioner)                   ┌────────────────────────────────────────────────┐   │
│                                                           │  80 vCPUs │ 640 GB RAM │ 8x H100 80GB NVL    │   │
│  ┌── Workspace YAML ───────────────────────┐             │  Total GPU VRAM: 640 GB                       │   │
│  │                                          │             │  NVLink interconnect (900 GB/s per GPU)       │   │
│  │  apiVersion: kaito.sh/v1beta1            │             │  InfiniBand: 400 Gb/s (multi-node capable)    │   │
│  │  kind: Workspace                         │             └────────────────────────────────────────────────┘   │
│  │  metadata:                               │                                                                  │
│  │    name: workspace-llama3                │                                                                  │
│  │  resource:                               │                                                                  │
│  │    instanceType: Standard_NC80adIS       │             ┌── Workspace Controller Reconciliation ──────────┐ │
│  │                   _H100_v5               │             │                                                  │ │
│  │    labelSelector:                        │             │  1. workspace-llama3 CR applied                  │ │
│  │      matchLabels:                        │───────────► │  2. Controller checks for matching GPU node      │ │
│  │        apps: llama3                      │             │  3. No match → creates Machine CR                │ │
│  │  inference:                              │             │  4. GPU Provisioner sees Machine CR              │ │
│  │    preset:                               │             │  5. Calls Azure ARM API → provisions NC80       │ │
│  │      name: meta-llama-3-70b-instruct     │             │  6. VM joins AKS as node (labels applied)       │ │
│  │                                          │             │  7. Controller creates Deployment + Service      │ │
│  │  # For 8B model:                         │             │  8. initContainer downloads model weights        │ │
│  │  # preset:                               │             │  9. vLLM starts, loads model into 8x H100       │ │
│  │  #   name: meta-llama-3-8b-instruct      │             │ 10. Pod becomes Ready, Service routes traffic    │ │
│  │  #   (can use smaller GPU, e.g.          │             │                                                  │ │
│  │  #    Standard_NV36ads_A10_v5)           │             └──────────────────────────────────────────────────┘ │
│  └──────────────────────────────────────────┘                                                                  │
│                                                                                                               │
│  ═══════ GENERATED K8s RESOURCES ═══════════════════════════════════════════════════════════════════════       │
│                                                                                                               │
│  ┌── GPU NODE: Standard_NC80adIS_H100_v5  │  Labels: apps=llama3 ────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  ┌── Deployment: workspace-llama3 ────────────────────────────────────────────────────────────────┐    │  │
│  │  │  Replicas: 1   │   Strategy: Recreate (GPU workload, no rolling update)                         │    │  │
│  │  │                                                                                                  │    │  │
│  │  │  ┌── Pod: workspace-llama3-xxxxx-xxxxx ──────────────────────────────────────────────────────┐  │    │  │
│  │  │  │                                                                                            │  │    │  │
│  │  │  │  initContainer: model-weights-downloader                                                   │  │    │  │
│  │  │  │  ├─ Image: mcr.microsoft.com/kaito/model-downloader:latest                                │  │    │  │
│  │  │  │  ├─ Downloads: meta-llama/Meta-Llama-3-70B-Instruct from HuggingFace                      │  │    │  │
│  │  │  │  ├─ Env: HF_TOKEN (from K8s Secret hf-token)                                              │  │    │  │
│  │  │  │  │  ↑ Llama 3 is a gated model — requires HuggingFace access token                        │  │    │  │
│  │  │  │  └─ Writes to: /workspace/vllm/weights (~140GB for 70B)                                   │  │    │  │
│  │  │  │                                                                                            │  │    │  │
│  │  │  │  container: vllm-inference                                                                 │  │    │  │
│  │  │  │  ├─ Image: mcr.microsoft.com/kaito/kaito-vllm:latest                                      │  │    │  │
│  │  │  │  ├─ Port: 5000                                                                             │  │    │  │
│  │  │  │  ├─ GPU: nvidia.com/gpu=8  (all 8x H100 GPUs)                                             │  │    │  │
│  │  │  │  ├─ Args: --model /workspace/vllm/weights                                                  │  │    │  │
│  │  │  │  │        --tensor-parallel-size 8      (shard 70B across 8 GPUs)                          │  │    │  │
│  │  │  │  │        --gpu-memory-utilization 0.9                                                     │  │    │  │
│  │  │  │  │        --max-model-len 8192          (Llama 3 supports 8K context)                      │  │    │  │
│  │  │  │  │        --dtype float16                                                                   │  │    │  │
│  │  │  │  ├─ Volume: /workspace/vllm/weights (emptyDir / hostPath)                                  │  │    │  │
│  │  │  │  └─ Probes:                                                                                │  │    │  │
│  │  │  │     ├─ liveness:  GET /health  (initialDelay: 600s — model loading takes ~10m)             │  │    │  │
│  │  │  │     └─ readiness: GET /health  (initialDelay: 600s)                                        │  │    │  │
│  │  │  │                                                                                            │  │    │  │
│  │  │  │  Exposed API (vLLM OpenAI-compatible):                                                     │  │    │  │
│  │  │  │  ├─ POST /v1/chat/completions   ← Main chat endpoint                                      │  │    │  │
│  │  │  │  ├─ POST /v1/completions        ← Text completion                                          │  │    │  │
│  │  │  │  ├─ GET  /v1/models             ← {"id":"meta-llama-3-70b-instruct",...}                   │  │    │  │
│  │  │  │  ├─ GET  /health                ← Health check                                             │  │    │  │
│  │  │  │  └─ GET  /metrics               ← Prometheus vLLM metrics                                  │  │    │  │
│  │  │  └────────────────────────────────────────────────────────────────────────────────────────────┘  │    │  │
│  │  └──────────────────────────────────────────────────────────────────────────────────────────────────┘    │  │
│  │                                                                                                        │  │
│  │  Service: workspace-llama3                  ServiceMonitor: workspace-llama3-metrics                    │  │
│  │  ├─ Type: ClusterIP                         ├─ Port: metrics (5000)                                    │  │
│  │  ├─ Port: 80 → 5000                         ├─ Path: /metrics                                          │  │
│  │  ├─ Selector: apps=llama3                   └─ Interval: 15s                                           │  │
│  │  └─ DNS: workspace-llama3.default                                                                      │  │
│  │         .svc.cluster.local                  Secret: hf-token                                            │  │
│  │                                              └─ HF_TOKEN: hf_xxxxx (HuggingFace gated access)          │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── GPU SKU Comparison (for Llama 3 models) ─────────────────────────────────────────────────────────────┐ │
│  │                                                                                                         │ │
│  │  Model              │ Parameters │ Min VRAM │ Recommended SKU                  │ Tensor Parallel       │ │
│  │  ────────────────── │ ────────── │ ──────── │ ──────────────────────────────── │ ──────────────────── │ │
│  │  Llama-3-8B         │ 8B         │ ~16 GB   │ Standard_NV36ads_A10_v5 (1xA10) │ 1                    │ │
│  │  Llama-3-70B        │ 70B        │ ~140 GB  │ Standard_NC80adIS_H100_v5       │ 8 (across 8x H100)  │ │
│  │                     │            │          │ (8xH100, 640GB)                  │                      │ │
│  │  Llama-3.1-405B     │ 405B       │ ~810 GB  │ Multi-node: 2x NC80 (16xH100)  │ 16 (distributed)     │ │
│  │                                                                                                         │ │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. RAG Process with PostgreSQL pgvector

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                               │
│  RAGEngine CRD — Using PostgreSQL (pgvector) as External Vector DB                                            │
│                                                                                                               │
│  NOTE: KAITO RAGEngine natively uses FAISS (in-memory). For PostgreSQL pgvector,                              │
│  the Streamlit app acts as the RAG orchestrator, connecting to:                                                │
│  (A) PostgreSQL pgvector for vector storage & search                                                          │
│  (B) KAITO Workspace (Llama 3) for LLM inference                                                              │
│                                                                                                               │
│  ┌── RAGEngine YAML (Option A: KAITO-native FAISS) ─────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  apiVersion: kaito.sh/v1alpha1                                                                         │  │
│  │  kind: RAGEngine                                                                                       │  │
│  │  metadata:                                                                                             │  │
│  │    name: rag-llama3                                                                                    │  │
│  │  spec:                                                                                                 │  │
│  │    compute:                                                                                            │  │
│  │      instanceType: Standard_NC4as_T4_v3        # T4 GPU for embedding                                 │  │
│  │      labelSelector:                                                                                    │  │
│  │        matchLabels:                                                                                    │  │
│  │          apps: ragengine-llama3                                                                        │  │
│  │    embedding:                                                                                          │  │
│  │      local:                                                                                            │  │
│  │        modelID: BAAI/bge-small-en-v1.5                                                                 │  │
│  │    inferenceService:                                                                                   │  │
│  │      url: http://workspace-llama3.default.svc.cluster.local/v1/completions                             │  │
│  │      contextWindowSize: 4096                                                                           │  │
│  │    storage:                                                                                            │  │
│  │      persistentVolumeClaim: pvc-ragengine-vector-db                                                    │  │
│  │      mountPath: /mnt/vector-db                                                                         │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── Option B: Custom RAG with PostgreSQL pgvector (Streamlit as orchestrator) ──────────────────────────┐  │
│  │                                                                                                        │  │
│  │  Streamlit Pod (app namespace) orchestrates the full RAG pipeline:                                     │  │
│  │                                                                                                        │  │
│  │  ┌─────────────────────────────────────────────────────────────────────────────────────────────────┐   │  │
│  │  │                                                                                                 │   │  │
│  │  │  ┌── INGEST FLOW (document upload) ──────────────────────────────────────────────────────────┐ │   │  │
│  │  │  │                                                                                            │ │   │  │
│  │  │  │  User uploads PDF/MD/TXT via Streamlit UI                                                  │ │   │  │
│  │  │  │       │                                                                                    │ │   │  │
│  │  │  │       ▼                                                                                    │ │   │  │
│  │  │  │  1. CHUNK: LangChain RecursiveCharacterTextSplitter                                        │ │   │  │
│  │  │  │     (chunk_size=512, overlap=128)                                                          │ │   │  │
│  │  │  │       │                                                                                    │ │   │  │
│  │  │  │       ▼                                                                                    │ │   │  │
│  │  │  │  2. EMBED: Call KAITO Workspace or sentence-transformers                                   │ │   │  │
│  │  │  │     POST http://workspace-llama3.../v1/embeddings                                          │ │   │  │
│  │  │  │     or local: SentenceTransformer("BAAI/bge-small-en-v1.5")                                │ │   │  │
│  │  │  │     → Vector[384] per chunk                                                                │ │   │  │
│  │  │  │       │                                                                                    │ │   │  │
│  │  │  │       ▼                                                                                    │ │   │  │
│  │  │  │  3. STORE: Insert into PostgreSQL pgvector                                                 │ │   │  │
│  │  │  │     ┌──────────────────────────────────────────────────────────────────────────────────┐   │ │   │  │
│  │  │  │     │  CREATE EXTENSION IF NOT EXISTS vector;                                          │   │ │   │  │
│  │  │  │     │                                                                                  │   │ │   │  │
│  │  │  │     │  CREATE TABLE embeddings (                                                       │   │ │   │  │
│  │  │  │     │    id            BIGSERIAL PRIMARY KEY,                                          │   │ │   │  │
│  │  │  │     │    content       TEXT NOT NULL,                                                   │   │ │   │  │
│  │  │  │     │    embedding     VECTOR(384) NOT NULL,    -- bge-small-en-v1.5 dimension         │   │ │   │  │
│  │  │  │     │    metadata      JSONB,                    -- source, page, chunk_idx            │   │ │   │  │
│  │  │  │     │    doc_id        UUID NOT NULL,                                                  │   │ │   │  │
│  │  │  │     │    created_at    TIMESTAMPTZ DEFAULT NOW()                                       │   │ │   │  │
│  │  │  │     │  );                                                                              │   │ │   │  │
│  │  │  │     │                                                                                  │   │ │   │  │
│  │  │  │     │  CREATE INDEX ON embeddings                                                      │   │ │   │  │
│  │  │  │     │    USING ivfflat (embedding vector_cosine_ops)                                   │   │ │   │  │
│  │  │  │     │    WITH (lists = 100);                                                           │   │ │   │  │
│  │  │  │     └──────────────────────────────────────────────────────────────────────────────────┘   │ │   │  │
│  │  │  └────────────────────────────────────────────────────────────────────────────────────────────┘ │   │  │
│  │  │                                                                                                 │   │  │
│  │  │  ┌── QUERY FLOW (user asks question) ────────────────────────────────────────────────────────┐ │   │  │
│  │  │  │                                                                                            │ │   │  │
│  │  │  │  User: "What is our refund policy?"                                                        │ │   │  │
│  │  │  │       │                                                                                    │ │   │  │
│  │  │  │       ▼                                                                                    │ │   │  │
│  │  │  │  1. EMBED QUERY: same model → Vector[384]                                                  │ │   │  │
│  │  │  │       │                                                                                    │ │   │  │
│  │  │  │       ▼                                                                                    │ │   │  │
│  │  │  │  2. VECTOR SEARCH in PostgreSQL:                                                           │ │   │  │
│  │  │  │     ┌──────────────────────────────────────────────────────────────────────────────────┐   │ │   │  │
│  │  │  │     │  SELECT content, metadata,                                                       │   │ │   │  │
│  │  │  │     │         1 - (embedding <=> $1::vector) AS similarity                             │   │ │   │  │
│  │  │  │     │  FROM embeddings                                                                 │   │ │   │  │
│  │  │  │     │  ORDER BY embedding <=> $1::vector                                               │   │ │   │  │
│  │  │  │     │  LIMIT 5;                                                                        │   │ │   │  │
│  │  │  │     │                                                                                  │   │ │   │  │
│  │  │  │     │  Returns: Top-5 most similar chunks with cosine similarity scores                │   │ │   │  │
│  │  │  │     └──────────────────────────────────────────────────────────────────────────────────┘   │ │   │  │
│  │  │  │       │                                                                                    │ │   │  │
│  │  │  │       ▼                                                                                    │ │   │  │
│  │  │  │  3. BUILD PROMPT: Inject retrieved chunks as context                                       │ │   │  │
│  │  │  │     System: "Answer based on the following context only."                                  │ │   │  │
│  │  │  │     Context: [chunk_1, chunk_2, ..., chunk_5]                                              │ │   │  │
│  │  │  │     User: "What is our refund policy?"                                                     │ │   │  │
│  │  │  │       │                                                                                    │ │   │  │
│  │  │  │       ▼                                                                                    │ │   │  │
│  │  │  │  4. LLM INFERENCE:                                                                         │ │   │  │
│  │  │  │     POST http://workspace-llama3.default.svc.cluster.local/v1/chat/completions             │ │   │  │
│  │  │  │     {"model":"meta-llama-3-70b-instruct",                                                  │ │   │  │
│  │  │  │      "messages": [{"role":"system","content":"Answer from context..."},                     │ │   │  │
│  │  │  │                   {"role":"user","content":"What is our refund policy?"}],                  │ │   │  │
│  │  │  │      "temperature": 0.3,                                                                   │ │   │  │
│  │  │  │      "max_tokens": 2048}                                                                   │ │   │  │
│  │  │  │       │                                                                                    │ │   │  │
│  │  │  │       ▼                                                                                    │ │   │  │
│  │  │  │  5. RESPONSE with sources:                                                                 │ │   │  │
│  │  │  │     "Our refund policy allows returns within 30 days..."                                   │ │   │  │
│  │  │  │     Sources: [policy.pdf (p.3), terms.md (§4.2)]                                           │ │   │  │
│  │  │  └────────────────────────────────────────────────────────────────────────────────────────────┘ │   │  │
│  │  └─────────────────────────────────────────────────────────────────────────────────────────────────┘   │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── PostgreSQL Flexible Server (Spoke 2: Data VNet) ────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  Server: kaito-rag-pgflex.postgres.database.azure.com                                                  │  │
│  │  SKU: Standard_D4ds_v5 (4 vCPU, 16 GB RAM)                                                            │  │
│  │  Storage: 128 GB (auto-grow enabled)                                                                   │  │
│  │  Version: PostgreSQL 16                                                                                │  │
│  │  Extension: pgvector v0.7.x                                                                            │  │
│  │  Auth: Microsoft Entra ID (passwordless) + Managed Identity from AKS                                   │  │
│  │                                                                                                        │  │
│  │  Private Endpoint: 10.2.0.4 (port 5432)                                                               │  │
│  │  Private DNS Zone: privatelink.postgres.database.azure.com                                             │  │
│  │                                                                                                        │  │
│  │  Database: ragdb                                                                                       │  │
│  │  ├─ Table: embeddings     (vector storage, IVFFlat index)                                              │  │
│  │  ├─ Table: documents      (original doc metadata, file_name, upload_date)                              │  │
│  │  └─ Table: chat_history   (user sessions, messages, timestamps)                                        │  │
│  │                                                                                                        │  │
│  │  Connection from AKS:                                                                                  │  │
│  │  postgresql://<mi-name>@kaito-rag-pgflex.postgres.database.azure.com:5432/ragdb?sslmode=require       │  │
│  │  (Using Workload Identity → Entra token → no password stored)                                          │  │
│  │                                                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. End-to-End Traffic Flow: Internet → Hub → AKS → Streamlit → RAG → PostgreSQL → Llama 3

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                               │
│  ═══ COMPLETE REQUEST FLOW ══════════════════════════════════════════════════════════════════════════════     │
│                                                                                                               │
│  ┌──────────┐                                                                                                │
│  │ INTERNET │                                                                                                │
│  │ User     │                                                                                                │
│  │ Browser  │                                                                                                │
│  └────┬─────┘                                                                                                │
│       │                                                                                                       │
│       │ ① HTTPS://ai.contoso.com                                                                             │
│       │    (DNS → Azure Public IP of App Gateway)                                                             │
│       ▼                                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐                          │
│  │  HUB VNET — Azure Application Gateway (WAF v2)                                  │                          │
│  │                                                                                  │                          │
│  │  ② WAF inspection:                                                               │                          │
│  │     ├─ OWASP Core Rule Set 3.2 (SQL injection, XSS, etc.)                       │                          │
│  │     ├─ Bot protection rules                                                      │                          │
│  │     ├─ Rate limiting: 100 req/min per IP                                         │                          │
│  │     ├─ Geo-filtering (optional: block certain regions)                            │                          │
│  │     └─ TLS termination (cert from Key Vault)                                     │                          │
│  │                                                                                  │                          │
│  │  ③ Route to backend pool: AKS Ingress internal LB (10.1.0.100)                  │                          │
│  │     (via VNet Peering Hub → Spoke 1)                                             │                          │
│  └──────────────────────────────────────┬──────────────────────────────────────────┘                          │
│                                          │                                                                     │
│       ┌──────────────────────────────────┤                                                                     │
│       │  HUB VNET — Azure Firewall       │                                                                     │
│       │                                  │                                                                     │
│       │  (Egress only — not in ingress   │                                                                     │
│       │  path. Controls outbound from    │                                                                     │
│       │  AKS: model downloads, PyPI,     │                                                                     │
│       │  container registry pulls)       │                                                                     │
│       └──────────────────────────────────┘                                                                     │
│                                          │                                                                     │
│                                          │ ④ VNet Peering (Hub → Spoke 1: AKS)                                │
│                                          ▼                                                                     │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐ │
│  │  SPOKE 1: AKS CLUSTER                                                                                   │ │
│  │                                                                                                          │ │
│  │  ⑤ NGINX Ingress Controller (LoadBalancer: 10.1.0.100)                                                  │ │
│  │     ├─ Receives request from App Gateway                                                                 │ │
│  │     ├─ TLS passthrough or re-encrypt                                                                     │ │
│  │     ├─ Host: ai.contoso.com → route to svc/streamlit-frontend                                           │ │
│  │     └─ Annotations: proxy-read-timeout=300 (long LLM calls)                                             │ │
│  │          │                                                                                               │ │
│  │          │ ⑥ ClusterIP routing                                                                           │ │
│  │          ▼                                                                                               │ │
│  │  ┌── svc/streamlit-frontend (ClusterIP, 80→8501) ──────────────────────────────────────────────────┐   │ │
│  │  │                                                                                                   │   │ │
│  │  │  Pod: streamlit-frontend-xxxxx (on System Node Pool)                                              │   │ │
│  │  │  ┌─────────────────────────────────────────────────────────────────────────────────────────────┐  │   │ │
│  │  │  │                                                                                              │  │   │ │
│  │  │  │  ⑦ Streamlit renders chat UI → User types: "What is our refund policy?"                     │  │   │ │
│  │  │  │                                                                                              │  │   │ │
│  │  │  │  ⑧ RAG PIPELINE (Python: LangChain + psycopg2 + pgvector):                                 │  │   │ │
│  │  │  │     │                                                                                        │  │   │ │
│  │  │  │     ├─ 8a. EMBED QUERY                                                                      │  │   │ │
│  │  │  │     │   SentenceTransformer("BAAI/bge-small-en-v1.5").encode(query)                         │  │   │ │
│  │  │  │     │   → query_vector[384]                                                                  │  │   │ │
│  │  │  │     │                                                                                        │  │   │ │
│  │  │  │     ├─ 8b. VECTOR SEARCH ──────────────────────────────────────────────────────────────┐    │  │   │ │
│  │  │  │     │   │                         SPOKE 2: DATA VNET                                    │    │  │   │ │
│  │  │  │     │   │  ⑨ SQL via Private Endpoint (10.2.0.4:5432)                                  │    │  │   │ │
│  │  │  │     │   │                                                                               │    │  │   │ │
│  │  │  │     │   │  ┌─────────────────────────────────────────────────────────────────────────┐ │    │  │   │ │
│  │  │  │     │   │  │  PostgreSQL Flexible Server (pgvector)                                  │ │    │  │   │ │
│  │  │  │     │   │  │                                                                         │ │    │  │   │ │
│  │  │  │     │   │  │  SELECT content, metadata,                                              │ │    │  │   │ │
│  │  │  │     │   │  │         1 - (embedding <=> $query_vector) AS score                      │ │    │  │   │ │
│  │  │  │     │   │  │  FROM embeddings                                                        │ │    │  │   │ │
│  │  │  │     │   │  │  ORDER BY embedding <=> $query_vector                                   │ │    │  │   │ │
│  │  │  │     │   │  │  LIMIT 5;                                                               │ │    │  │   │ │
│  │  │  │     │   │  │                                                                         │ │    │  │   │ │
│  │  │  │     │   │  │  → Returns 5 relevant chunks with similarity scores                     │ │    │  │   │ │
│  │  │  │     │   │  └─────────────────────────────────────────────────────────────────────────┘ │    │  │   │ │
│  │  │  │     │   └──────────────────────────────────────────────────────────────────────────────┘    │  │   │ │
│  │  │  │     │                                                                                        │  │   │ │
│  │  │  │     ├─ 8c. BUILD AUGMENTED PROMPT                                                            │  │   │ │
│  │  │  │     │   system = "Answer based on context only. Cite sources."                               │  │   │ │
│  │  │  │     │   context = [chunk_1, chunk_2, chunk_3, chunk_4, chunk_5]                              │  │   │ │
│  │  │  │     │   user = "What is our refund policy?"                                                  │  │   │ │
│  │  │  │     │                                                                                        │  │   │ │
│  │  │  │     └─ 8d. LLM INFERENCE ──────────────────────────────────────────────────────────────┐    │  │   │ │
│  │  │  │         │                         DEFAULT NAMESPACE                                     │    │  │   │ │
│  │  │  │         │  ⑩ POST http://workspace-llama3.default.svc.cluster.local                    │    │  │   │ │
│  │  │  │         │         /v1/chat/completions                                                  │    │  │   │ │
│  │  │  │         │                                                                               │    │  │   │ │
│  │  │  │         │  ┌─────────────────────────────────────────────────────────────────────────┐ │    │  │   │ │
│  │  │  │         │  │  svc/workspace-llama3 (ClusterIP 80→5000)                               │ │    │  │   │ │
│  │  │  │         │  │       │                                                                  │ │    │  │   │ │
│  │  │  │         │  │       ▼                                                                  │ │    │  │   │ │
│  │  │  │         │  │  Pod: workspace-llama3-xxxxx (GPU Node: NC80 - 8x H100)                 │ │    │  │   │ │
│  │  │  │         │  │  ┌───────────────────────────────────────────────────────────────────┐  │ │    │  │   │ │
│  │  │  │         │  │  │  vLLM inference engine                                            │  │ │    │  │   │ │
│  │  │  │         │  │  │  Model: meta-llama-3-70b-instruct                                 │  │ │    │  │   │ │
│  │  │  │         │  │  │  Tensor Parallel: 8 (sharded across 8x H100 GPUs)                 │  │ │    │  │   │ │
│  │  │  │         │  │  │  GPU VRAM: ~140GB used / 640GB total                              │  │ │    │  │   │ │
│  │  │  │         │  │  │                                                                    │  │ │    │  │   │ │
│  │  │  │         │  │  │  Input: augmented prompt with RAG context                         │  │ │    │  │   │ │
│  │  │  │         │  │  │  Output: "Our refund policy allows returns within 30 days of      │  │ │    │  │   │ │
│  │  │  │         │  │  │           purchase. [Source: policy.pdf p.3]"                      │  │ │    │  │   │ │
│  │  │  │         │  │  └───────────────────────────────────────────────────────────────────┘  │ │    │  │   │ │
│  │  │  │         │  └─────────────────────────────────────────────────────────────────────────┘ │    │  │   │ │
│  │  │  │         └──────────────────────────────────────────────────────────────────────────────┘    │  │   │ │
│  │  │  │                                                                                              │  │   │ │
│  │  │  │  ⑪ Streamlit renders response with source citations                                         │  │   │ │
│  │  │  │     ├─ Chat bubble: "Our refund policy allows returns within 30 days..."                    │  │   │ │
│  │  │  │     └─ Sources: policy.pdf (p.3, score: 0.95), terms.md (§4.2, score: 0.88)                │  │   │ │
│  │  │  │                                                                                              │  │   │ │
│  │  │  └─────────────────────────────────────────────────────────────────────────────────────────────┘  │   │ │
│  │  └───────────────────────────────────────────────────────────────────────────────────────────────────┘   │ │
│  │                                                                                                          │ │
│  │  ⑫ Response travels back:                                                                               │ │
│  │     Streamlit Pod → svc/streamlit-frontend → Ingress Controller → App Gateway → Internet → User Browser  │ │
│  │                                                                                                          │ │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                                               │
│  ═══ LATENCY BREAKDOWN (typical) ════════════════════════════════════════════════════════════════════════     │
│                                                                                                               │
│  ① → ③  App Gateway (WAF + routing)         :   ~5 ms                                                       │
│  ④ → ⑥  Ingress → Service routing           :   ~2 ms                                                       │
│  ⑧a     Embed query (bge-small on CPU)       :  ~20 ms                                                       │
│  ⑧b     pgvector search (IVFFlat, top-5)     :  ~10 ms                                                       │
│  ⑧c     Prompt construction                  :   ~1 ms                                                       │
│  ⑧d     Llama-3-70B inference (8xH100)       : ~500-3000 ms (depends on max_tokens)                          │
│  ⑪      Streamlit render                     :   ~5 ms                                                       │
│  ─────────────────────────────────────────────                                                                │
│  Total                                       : ~550 - 3050 ms                                                 │
│                                                                                                               │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Summary — All Components at a Glance

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                               │
│  COMPONENT            │ RESOURCE / SKU                           │ PURPOSE                                    │
│  ─────────────────── │ ──────────────────────────────────────── │ ──────────────────────────────────────────│
│  App Gateway (WAF v2) │ Standard_v2, AppGwSubnet                │ HTTPS termination, WAF, routing to AKS    │
│  Azure Firewall       │ Premium, AzureFirewallSubnet            │ Egress filtering (HF, MCR, PyPI)          │
│  AKS System Pool      │ 3x Standard_D4s_v5                     │ K8s system + Streamlit + Ingress          │
│  AKS GPU Pool         │ 1x Standard_NC80adIS_H100_v5           │ Llama-3-70B inference (8x H100)           │
│  KAITO Workspace      │ workspace-llama3 (Llama 3 70B preset)  │ vLLM server, OpenAI-compatible API        │
│  KAITO RAGEngine      │ rag-llama3 (optional FAISS approach)   │ Native RAG with FAISS + bge-small         │
│  Streamlit Frontend   │ 2x replicas, Deployment in app ns      │ Chat UI + RAG orchestrator (pgvector)     │
│  NGINX Ingress        │ Internal LB (10.1.0.100)               │ Route: ai.contoso.com → streamlit svc     │
│  PostgreSQL Flex      │ Standard_D4ds_v5, pgvector ext          │ Vector storage (384d), doc store, history │
│  Key Vault            │ Standard                                │ TLS certs, HF token, PG credentials      │
│  ACR (Private)        │ Premium                                 │ KAITO + Streamlit container images        │
│  Entra ID + MI        │ Workload Identity                      │ Passwordless auth AKS → PostgreSQL        │
│  Azure Monitor        │ Prometheus + Grafana                   │ vLLM metrics, GPU utilization, latency    │
│                                                                                                               │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```
