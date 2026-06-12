# KAITO on AKS - Full Architecture (Hub-Spoke + Kubernetes + RAG)

## 1. High-Level Hub-Spoke Azure Network Topology

```
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                     AZURE CLOUD (Indonesia Central / East US)                               │
│                                                                                                             │
│  ┌─── HUB VNET (10.0.0.0/16) ──────────────────────────────────────────────────────────────────────────┐   │
│  │                                                                                                       │   │
│  │  ┌─────────────────────┐   ┌──────────────────────┐   ┌──────────────────────────────────────────┐   │   │
│  │  │  Azure Firewall     │   │  Azure Bastion       │   │  VPN / ExpressRoute Gateway             │   │   │
│  │  │  (AzureFirewallSub) │   │  (AzureBastionSub)   │   │  (GatewaySubnet)                        │   │   │
│  │  │  10.0.1.0/26        │   │  10.0.2.0/26         │   │  10.0.3.0/27                            │   │   │
│  │  │                     │   │                      │   │                                          │   │   │
│  │  │  ┌───────────────┐  │   │  SSH/RDP to Jump     │   │  On-Prem ◄──── ExpressRoute ────► Azure │   │   │
│  │  │  │ Egress Filter │  │   │  Boxes & AKS Nodes   │   │  Users   ◄──── S2S VPN ─────► Azure    │   │   │
│  │  │  │ - HuggingFace │  │   │                      │   │                                          │   │   │
│  │  │  │ - MCR         │  │   └──────────────────────┘   └──────────────────────────────────────────┘   │   │
│  │  │  │ - Monitoring  │  │                                                                              │   │
│  │  │  └───────────────┘  │   ┌──────────────────────┐   ┌──────────────────────────────────────────┐   │   │
│  │  └─────────────────────┘   │  Azure DNS Private   │   │  Azure Monitor / Log Analytics          │   │   │
│  │                            │  Resolver             │   │  ┌────────────────────────────────────┐ │   │   │
│  │                            │  - AKS private DNS    │   │  │ Prometheus (Azure Monitor Wksp)   │ │   │   │
│  │                            │  - ACR private DNS    │   │  │ Grafana (vLLM Dashboard)           │ │   │   │
│  │                            │  - Storage private    │   │  │ Log Analytics Workspace            │ │   │   │
│  │                            └──────────────────────┘   │  └────────────────────────────────────┘ │   │   │
│  │                                                        └──────────────────────────────────────────┘   │   │
│  └───────────────────────────────────────────────────────────────────────────────────────────────────────┘   │
│             │ VNet Peering                  │ VNet Peering                      │ VNet Peering               │
│             │                               │                                   │                            │
│  ┌──────────▼──── SPOKE 1 ──────────┐  ┌───▼──── SPOKE 2 ──────────┐  ┌───────▼── SPOKE 3 ──────────┐     │
│  │  AKS VNET (10.1.0.0/16)         │  │  DATA VNET (10.2.0.0/16)  │  │  APP VNET (10.3.0.0/16)     │     │
│  │  ┌─────────────────────────┐     │  │                            │  │                              │     │
│  │  │ AKS Cluster (KAITO)    │     │  │  ┌──────────────────────┐  │  │  ┌────────────────────────┐  │     │
│  │  │ with AI Toolchain Op.  │     │  │  │ Azure AI Search      │  │  │  │ App Service / ACA      │  │     │
│  │  │ (see K8s diagram below)│     │  │  │ (Vector Index)       │  │  │  │ (Frontend / API)       │  │     │
│  │  └─────────────────────────┘     │  │  └──────────────────────┘  │  │  └────────────────────────┘  │     │
│  │                                   │  │  ┌──────────────────────┐  │  │  ┌────────────────────────┐  │     │
│  │  ┌─────────────────────────┐     │  │  │ Azure Cosmos DB      │  │  │  │ Azure API Management   │  │     │
│  │  │ ACR (Private Endpoint) │     │  │  │ (Doc Store / Chat)   │  │  │  │ (Rate Limit, Auth)     │  │     │
│  │  │ KAITO container images │     │  │  └──────────────────────┘  │  │  └────────────────────────┘  │     │
│  │  └─────────────────────────┘     │  │  ┌──────────────────────┐  │  │  ┌────────────────────────┐  │     │
│  │  ┌─────────────────────────┐     │  │  │ Azure Storage        │  │  │  │ Streamlit UI           │  │     │
│  │  │ Key Vault              │     │  │  │ (Documents / Blobs)  │  │  │  │ (Chat Interface)       │  │     │
│  │  │ (HF Token, Secrets)    │     │  │  └──────────────────────┘  │  │  └────────────────────────┘  │     │
│  │  └─────────────────────────┘     │  │  ┌──────────────────────┐  │  │                              │     │
│  │                                   │  │  │ Azure OpenAI         │  │  │                              │     │
│  │  Subnet: 10.1.0.0/20 (AKS)      │  │  │ (Embeddings Model)  │  │  │                              │     │
│  │  Subnet: 10.1.16.0/24 (PE)      │  │  └──────────────────────┘  │  │                              │     │
│  └───────────────────────────────────┘  └────────────────────────────┘  └──────────────────────────────┘     │
│                                                                                                             │
│  ┌── SHARED SERVICES ──────────────────────────────────────────────────────────────────────────────────┐    │
│  │  Microsoft Entra ID          ──── RBAC / Managed Identity / Workload Identity / OIDC Issuer        │    │
│  │  Azure Policy (Gatekeeper)   ──── Enforce GPU SKU limits, namespace isolation, network policies    │    │
│  │  Microsoft Defender for Cloud ──── Runtime threat detection for AKS & containers                   │    │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. AKS Cluster — Detailed K8s Resources (Namespaces, Deployments, Services, Pods, CRDs)

> Source: [KAITO Official Docs v0.9.x](https://kaito-project.github.io/kaito/docs/)
> The **Workspace controller** reconciles the `workspace` CR and creates `machine` CRs
> to trigger node auto-provisioning, then creates the inference workload
> (`Deployment`, `StatefulSet`, or `Job`) based on model preset configurations.

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                               AKS CLUSTER (KAITO + RAGEngine Enabled)                                         │
│                               --enable-ai-toolchain-operator  --enable-oidc-issuer                            │
│                               Network Plugin: Azure CNI Overlay                                               │
├──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                               │
│  ┌── NAMESPACE: kube-system ──────────────────────────────────────────────────────────────────────────────┐  │
│  │  System components (managed by AKS)                                                                     │  │
│  │                                                                                                         │  │
│  │  Deployment: coredns                    Deployment: metrics-server      DaemonSet: kube-proxy           │  │
│  │  └─ Pod: coredns-xxxxx (×2)             └─ Pod: metrics-server-xxx      └─ Pod: kube-proxy-xxx (×N)    │  │
│  │                                                                                                         │  │
│  │  DaemonSet: nvidia-device-plugin-daemonset (on GPU nodes only)                                          │  │
│  │  └─ Pod: nvidia-device-plugin-xxx       Exposes nvidia.com/gpu resource to K8s scheduler               │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── NAMESPACE: kaito-workspace ──────────────────────────────────────────────────────────────────────────┐  │
│  │  Installed via: helm install kaito-workspace kaito/workspace -n kaito-workspace                         │  │
│  │                                                                                                         │  │
│  │  ┌─── Deployment: kaito-workspace ──────────────────────────────────────────────────────────────────┐  │  │
│  │  │  Replicas: 1                                                                                      │  │  │
│  │  │  ┌─── Pod: kaito-workspace-xxxxx ─────────────────────────────────────────────────────────────┐   │  │  │
│  │  │  │  Container: manager                                                                         │   │  │  │
│  │  │  │                                                                                             │   │  │  │
│  │  │  │  WATCHES (Custom Resources):              CREATES (per Workspace CR):                       │   │  │  │
│  │  │  │  ├─ Workspace    (kaito.sh/v1beta1)       ├─ Machine CRs ──► gpu-provisioner                │   │  │  │
│  │  │  │  │                                         ├─ Deployment / StatefulSet / Job                 │   │  │  │
│  │  │  │  │                                         │   (vLLM inference workload)                     │   │  │  │
│  │  │  │  │                                         ├─ Service (ClusterIP, port 80)                   │   │  │  │
│  │  │  │  │                                         └─ ConfigMaps (inference config)                  │   │  │  │
│  │  │  │  │                                                                                           │   │  │  │
│  │  │  │  RECONCILIATION LOOP:                                                                        │   │  │  │
│  │  │  │  1. User applies Workspace CR                                                                │   │  │  │
│  │  │  │  2. Controller validates GPU SKU + preset name                                               │   │  │  │
│  │  │  │  3. Creates Machine CR → gpu-provisioner provisions GPU node                                 │   │  │  │
│  │  │  │  4. Creates Deployment (vLLM Pod with init container for model download)                     │   │  │  │
│  │  │  │  5. Creates ClusterIP Service (name = workspace name)                                        │   │  │  │
│  │  │  │  6. Updates Workspace status: ResourceReady → InferenceReady → WorkspaceSucceeded            │   │  │  │
│  │  │  └─────────────────────────────────────────────────────────────────────────────────────────────┘   │  │  │
│  │  └──────────────────────────────────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                                                         │  │
│  │  Service: kaito-workspace-metrics  (port 8443, for controller metrics)                                  │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── NAMESPACE: gpu-provisioner ──────────────────────────────────────────────────────────────────────────┐  │
│  │  Installed via: helm install gpu-provisioner (Karpenter-based, Azure-specific)                           │  │
│  │                                                                                                         │  │
│  │  Deployment: gpu-provisioner                                                                             │  │
│  │  └─ Pod: gpu-provisioner-xxxxx                                                                           │  │
│  │     Container: controller                                                                                │  │
│  │     ├─ Watches: Machine CRs (from Workspace controller)                                                 │  │
│  │     ├─ Calls: Azure Resource Manager REST APIs                                                           │  │
│  │     ├─ Creates: GPU VM nodes in AKS                                                                     │  │
│  │     └─ Manages: NodeClaim lifecycle (provision / deprovision)                                            │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── NAMESPACE: kaito-ragengine ──────────────────────────────────────────────────────────────────────────┐  │
│  │  Installed via: helm install kaito-ragengine kaito/ragengine -n kaito-ragengine                         │  │
│  │                                                                                                         │  │
│  │  Deployment: ragengine                                                                                   │  │
│  │  └─ Pod: ragengine-xxxxx                                                                                 │  │
│  │     Container: manager                                                                                   │  │
│  │     ├─ Watches: RAGEngine CRs (kaito.sh/v1alpha1)                                                      │  │
│  │     ├─ Creates: RAGService Deployment (with LlamaIndex + FAISS + Embedding model)                       │  │
│  │     ├─ Creates: ClusterIP Service for RAG API                                                            │  │
│  │     └─ Needs: gpu-provisioner for auto-provisioning GPU nodes for local embedding                       │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── SYSTEM NODE POOL (Standard_D4s_v3, no GPU) ─────────────────────────────────────────────────────────┐  │
│  │  ┌──────────────────────┐                                                                               │  │
│  │  │  Node: aks-system-xxx│  Runs: kaito-workspace, gpu-provisioner, ragengine controllers,              │  │
│  │  │  4 vCPU / 16 GB RAM  │         CoreDNS, kube-proxy, metrics-server                                  │  │
│  │  │  Taint:              │  Taint: CriticalAddonsOnly=true:NoSchedule                                   │  │
│  │  │   CriticalAddonsOnly │                                                                               │  │
│  │  └──────────────────────┘                                                                               │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ══════════════════════════════════════════════════════════════════════════════════════════════════════════    │
│  DEFAULT NAMESPACE — User Workloads (Workspace + RAGEngine CRs and their generated K8s resources)            │
│  ══════════════════════════════════════════════════════════════════════════════════════════════════════════    │
│                                                                                                               │
│  ┌── CRD: Workspace (kaito.sh/v1beta1) ──────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                         │  │
│  │  apiVersion: kaito.sh/v1beta1           STATUS COLUMNS (kubectl get workspace):                         │  │
│  │  kind: Workspace                        ┌────────────────────────────────────────────────────────────┐  │  │
│  │  metadata:                              │ NAME                    INSTANCE               RESOURCE   │  │  │
│  │    name: workspace-phi-4-mini-instruct  │                                                READY      │  │  │
│  │  resource:                              │ workspace-phi-4-mini    Standard_NV36ads_A10   True       │  │  │
│  │    instanceType: Standard_NV36ads_A10   │                                                            │  │  │
│  │    labelSelector:                       │ INFERENCEREADY  WORKSPACESUCCEEDED  AGE                   │  │  │
│  │      matchLabels:                       │ True            True                4h15m                  │  │  │
│  │        apps: phi-4-mini-instruct        └────────────────────────────────────────────────────────────┘  │  │
│  │  inference:                                                                                             │  │
│  │    preset:                              Status Conditions:                                              │  │
│  │      name: phi-4-mini-instruct           1. ResourceReady:  Pending → True  (GPU node provisioned)     │  │
│  │    config: phi4-inference-config         2. InferenceReady: Pending → True  (model loaded & serving)   │  │
│  │                                          3. WorkspaceSucceeded: True        (all healthy)              │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                        │                                                                                      │
│                        │  Workspace controller reconciles → creates the following K8s resources:              │
│                        ▼                                                                                      │
│  ┌── Generated: Deployment ──────────────────────────────────────────────────────────────────────────────┐   │
│  │  Deployment: workspace-phi-4-mini-instruct                                                             │   │
│  │  Namespace: default                                                                                    │   │
│  │  Replicas: 1                                                                                           │   │
│  │  Selector: apps=phi-4-mini-instruct                                                                    │   │
│  │  Node Selector: via Machine CR labels                                                                  │   │
│  │                                                                                                         │   │
│  │  ┌─── Pod: workspace-phi-4-mini-instruct-xxxxx ────────────────────────────────────────────────────┐  │   │
│  │  │  Scheduled on: GPU Node (Standard_NV36ads_A10_v5, 1x NVIDIA A10, 24GB VRAM)                     │  │   │
│  │  │  Labels: apps=phi-4-mini-instruct, kaito.sh/workspace=workspace-phi-4-mini-instruct              │  │   │
│  │  │                                                                                                   │  │   │
│  │  │  ┌─ initContainer: model-weights-downloader ─────────────────────────────────────────────────┐   │  │   │
│  │  │  │  Image: mcr.microsoft.com/kaito/kaito-model-downloader:latest                              │   │  │   │
│  │  │  │  Action: Downloads model weights from HuggingFace Hub or MCR cache                         │   │  │   │
│  │  │  │  Volume: /workspace/vllm/weights (emptyDir or PVC)                                         │   │  │   │
│  │  │  │  Env: HF_TOKEN (from Secret, for gated models like llama)                                  │   │  │   │
│  │  │  └────────────────────────────────────────────────────────────────────────────────────────────┘   │  │   │
│  │  │                                                                                                   │  │   │
│  │  │  ┌─ container: vllm-inference ───────────────────────────────────────────────────────────────┐   │  │   │
│  │  │  │  Image: mcr.microsoft.com/kaito/kaito-vllm:latest (or transformers runtime)               │   │  │   │
│  │  │  │  Port: 5000 (containerPort)                                                                │   │  │   │
│  │  │  │  Args: --model /workspace/vllm/weights                                                     │   │  │   │
│  │  │  │        --gpu-memory-utilization 0.85                                                        │   │  │   │
│  │  │  │        --max-model-len 65536                                                                │   │  │   │
│  │  │  │                                                                                             │   │  │   │
│  │  │  │  Resources:                          Endpoints (OpenAI-Compatible):                         │   │  │   │
│  │  │  │    requests:                          POST /v1/chat/completions                             │   │  │   │
│  │  │  │      nvidia.com/gpu: 1                POST /v1/completions                                  │   │  │   │
│  │  │  │    limits:                            GET  /v1/models                                       │   │  │   │
│  │  │  │      nvidia.com/gpu: 1                GET  /health                                          │   │  │   │
│  │  │  │                                       GET  /metrics  (Prometheus vLLM metrics)              │   │  │   │
│  │  │  │  VolumeMount: /workspace/vllm/weights (model weights from init container)                  │   │  │   │
│  │  │  │  Probes:                                                                                    │   │  │   │
│  │  │  │    livenessProbe:  GET /health                                                              │   │  │   │
│  │  │  │    readinessProbe: GET /health                                                              │   │  │   │
│  │  │  └────────────────────────────────────────────────────────────────────────────────────────────┘   │  │   │
│  │  └───────────────────────────────────────────────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                               │
│  ┌── Generated: Service ─────────────────────┐     ┌── User-Created: ConfigMap ───────────────────────┐      │
│  │  Service: workspace-phi-4-mini-instruct   │     │  ConfigMap: phi4-inference-config                 │      │
│  │  Namespace: default                       │     │  Namespace: default                               │      │
│  │  Type: ClusterIP                          │     │  data:                                            │      │
│  │  Port: 80 → targetPort: 5000             │     │    inference_config.yaml: |                       │      │
│  │  Selector: apps=phi-4-mini-instruct       │     │      max_probe_steps: 6                          │      │
│  │                                            │     │      vllm:                                       │      │
│  │  Cluster DNS:                              │     │        gpu-memory-utilization: 0.85              │      │
│  │  workspace-phi-4-mini-instruct             │     │        max-model-len: 65536                     │      │
│  │   .default.svc.cluster.local              │     │        cpu-offload-gb: 0                         │      │
│  │                                            │     │        swap-space: 4                             │      │
│  │  Access Methods:                           │     └──────────────────────────────────────────────────┘      │
│  │  1. kubectl port-forward svc/... 8080:80  │                                                                │
│  │  2. ClusterIP from other pods              │     ┌── User-Created: Secret (gated models) ──────────┐      │
│  │  3. Ingress / Gateway (production)         │     │  Secret: hf-token                                │      │
│  │                                            │     │  Type: Opaque                                    │      │
│  │  Endpoint: {Pod IP}:5000                   │     │  data:                                           │      │
│  └────────────────────────────────────────────┘     │    HF_TOKEN: <base64-encoded HF token>          │      │
│                                                      │  Required for: llama, gemma (gated models)      │      │
│  ┌── User-Created: ServiceMonitor ───────────┐     │  Referenced in: workspace.inference.preset       │      │
│  │  ServiceMonitor:                           │     │    .presetOptions.modelAccessSecret: hf-token    │      │
│  │    workspace-phi-4-mini-instruct-monitor   │     └──────────────────────────────────────────────────┘      │
│  │  API: azmonitoring.coreos.com/v1           │                                                               │
│  │  Selector: kaito.sh/workspace=...          │                                                               │
│  │  Endpoint: port http, path /metrics        │                                                               │
│  │  Interval: 30s                             │                                                               │
│  │  → Scraped by Azure Managed Prometheus     │                                                               │
│  │  → Visualized in Azure Managed Grafana     │                                                               │
│  └────────────────────────────────────────────┘                                                               │
│                                                                                                               │
│  ┌── HEADLAMP (Desktop App + KAITO Plugin) ──────────────────────────────────────────────────────────────┐  │
│  │  Runs on: Developer workstation (Windows/Mac/Linux) — reads ~/.kube/config                             │  │
│  │                                                                                                         │  │
│  │  ┌─────────────────────┐  ┌──────────────────────┐  ┌──────────────────────────────────┐               │  │
│  │  │  Cluster Dashboard  │  │  KAITO Plugin         │  │  Built-in Chat Interface         │               │  │
│  │  │  - Nodes / Pods     │  │  - Model Catalog      │  │  - Select workspace              │               │  │
│  │  │  - Deployments      │  │  - Kaito Workspaces   │  │  - Send prompts                  │               │  │
│  │  │  - Services         │  │  - Deploy with GUI    │  │  - View responses                │               │  │
│  │  │  - Events/Logs      │  │  - Status monitoring   │  │  - Adjust parameters             │               │  │
│  │  └─────────────────────┘  └──────────────────────┘  └──────────────────────────────────┘               │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Multi-Node Architecture with llm-d (Prefill/Decode Disaggregation)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                        AKS CLUSTER - Multi-Node (3x Standard_NV12ads_A10_v5)                                  │
│                                                                                                               │
│  ┌── Gateway API Inference Extension Layer ──────────────────────────────────────────────────────────────┐   │
│  │                                                                                                        │   │
│  │  Client ──► ┌──────────────────────────────────────────────────────────────────┐                      │   │
│  │             │  Gateway (llmd-inference-gateway)                                 │                      │   │
│  │             │  gatewayClassName: llm-d                                          │                      │   │
│  │             │  Port: 8080/HTTP                                                  │                      │   │
│  │             └────────────────────────────┬─────────────────────────────────────┘                      │   │
│  │                                          │                                                             │   │
│  │                                          ▼                                                             │   │
│  │             ┌──────────────────────────────────────────────────────────────────┐                      │   │
│  │             │  HTTPRoute (llmd-model-route)                                    │                      │   │
│  │             │  PathPrefix: /v1  ─────►  InferencePool                          │                      │   │
│  │             └────────────────────────────┬─────────────────────────────────────┘                      │   │
│  │                                          │                                                             │   │
│  │                                          ▼                                                             │   │
│  │             ┌──────────────────────────────────────────────────────────────────┐                      │   │
│  │             │  InferencePool (kaito-gpt-oss-20b-pool)                          │                      │   │
│  │             │  targetRef: Service/workspace-gpt-oss-20b                        │                      │   │
│  │             │  scheduling:                                                     │                      │   │
│  │             │    prefixCacheAware: true                                        │                      │   │
│  │             │    loadBalancing: least-loaded                                   │                      │   │
│  │             └────────────────────────────┬─────────────────────────────────────┘                      │   │
│  │                                          │                                                             │   │
│  │             ┌──────────────────────────────────────────────────────────────────┐                      │   │
│  │             │  InferenceModel (gpt-oss-20b)                                    │                      │   │
│  │             │  poolRef: kaito-gpt-oss-20b-pool                                │                      │   │
│  │             │  criticality: Standard                                            │                      │   │
│  │             └──────────────────────────────────────────────────────────────────┘                      │   │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                          │                                                                    │
│                    ┌─────────────────────┼─────────────────────┐                                              │
│                    │                     │                     │                                              │
│                    ▼                     ▼                     ▼                                              │
│  ┌─── GPU Node 1 ─────────┐  ┌─── GPU Node 2 ─────────┐  ┌─── GPU Node 3 ─────────┐                       │
│  │  NV12ads_A10_v5         │  │  NV12ads_A10_v5         │  │  NV12ads_A10_v5         │                       │
│  │  12 vCPU / 110GB RAM    │  │  12 vCPU / 110GB RAM    │  │  12 vCPU / 110GB RAM    │                       │
│  │                         │  │                         │  │                         │                       │
│  │  ╔═══════════════════╗  │  │  ╔═══════════════════╗  │  │  ╔═══════════════════╗  │                       │
│  │  ║  NVIDIA A10       ║  │  │  ║  NVIDIA A10       ║  │  │  ║  NVIDIA A10       ║  │                       │
│  │  ║  8GB GDDR6 (1/3)  ║  │  │  ║  8GB GDDR6 (1/3)  ║  │  │  ║  8GB GDDR6 (1/3)  ║  │                       │
│  │  ║                   ║  │  │  ║                   ║  │  │  ║                   ║  │                       │
│  │  ║  vLLM Pod         ║  │  │  ║  vLLM Pod         ║  │  │  ║  vLLM Pod         ║  │                       │
│  │  ║  Role: PREFILL    ║  │  │  ║  Role: DECODE     ║  │  │  ║  Role: DECODE     ║  │                       │
│  │  ║  (prompt proc.)   ║  │  │  ║  (token gen.)     ║  │  │  ║  (token gen.)     ║  │                       │
│  │  ╚═══════╦═══════════╝  │  │  ╚═══════╦═══════════╝  │  │  ╚═══════╦═══════════╝  │                       │
│  └──────────╬──────────────┘  └──────────╬──────────────┘  └──────────╬──────────────┘                       │
│             │                            │                            │                                       │
│             └────────────────────────────┼────────────────────────────┘                                       │
│                                          │                                                                    │
│                               ┌──────────┴──────────┐                                                        │
│                               │   NIXL KV Transfer   │                                                        │
│                               │  (GPU-to-GPU direct) │                                                        │
│                               │  KV cache sharing    │                                                        │
│                               │  No CPU bottleneck   │                                                        │
│                               └─────────────────────┘                                                        │
│                                                                                                               │
│  Total GPU Memory: 24GB (3 x 8GB)   Model: gpt-oss-20b (~12.9 GiB weights)                                  │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. RAG Scenario — Complete K8s Resources (Deployments, Services, Pods, CRDs, APIs)

> Source: [KAITO RAG Docs](https://kaito-project.github.io/kaito/docs/rag) &
> [RAG API Reference](https://kaito-project.github.io/kaito/docs/rag-api)
>
> RAGEngine controller reconciles the `ragengine` CR and creates a `RAGService` Deployment.
> The RAGService uses **LlamaIndex** as orchestrator, **FAISS** as in-memory vector DB,
> and supports **local** or **remote** embedding models.

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                               │
│                    COMPLETE RAG SCENARIO — ALL K8s RESOURCES ON AKS                                           │
│                                                                                                               │
│  ┌─ Step 1: Install Controllers (Helm) ──────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  # 1. Workspace controller (for LLM inference)                                                         │  │
│  │  helm install kaito-workspace kaito/workspace -n kaito-workspace --create-namespace                    │  │
│  │                                                                                                        │  │
│  │  # 2. RAGEngine controller (for RAG service)                                                           │  │
│  │  helm install kaito-ragengine kaito/ragengine -n kaito-ragengine --create-namespace                    │  │
│  │                                                                                                        │  │
│  │  # 3. GPU provisioner (for auto-provisioning GPU nodes)                                                │  │
│  │  helm install gpu-provisioner gpu-provisioner/gpu-provisioner -n gpu-provisioner --create-namespace     │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌─ Step 2: Apply CRDs ─────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  ┌── CRD 1: Workspace (LLM Backend) ────────────┐  ┌── CRD 2: RAGEngine (RAG Service) ────────────┐  │  │
│  │  │                                                │  │                                               │  │  │
│  │  │  apiVersion: kaito.sh/v1beta1                  │  │  apiVersion: kaito.sh/v1alpha1                │  │  │
│  │  │  kind: Workspace                               │  │  kind: RAGEngine                              │  │  │
│  │  │  metadata:                                     │  │  metadata:                                    │  │  │
│  │  │    name: workspace-phi-4-mini-instruct         │  │    name: rag-phi4                             │  │  │
│  │  │  resource:                                     │  │  spec:                                        │  │  │
│  │  │    instanceType: Standard_NV36ads_A10_v5       │  │    compute:                                   │  │  │
│  │  │    labelSelector:                              │  │      instanceType: Standard_NC4as_T4_v3       │  │  │
│  │  │      matchLabels:                              │  │      labelSelector:                            │  │  │
│  │  │        apps: phi-4-mini-instruct               │  │        matchLabels:                            │  │  │
│  │  │  inference:                                    │  │          apps: ragengine-phi4                  │  │  │
│  │  │    preset:                                     │  │    storage:                   # Optional PVC   │  │  │
│  │  │      name: phi-4-mini-instruct                 │  │      persistentVolumeClaim:                   │  │  │
│  │  │    config: phi4-inference-config               │  │        pvc-ragengine-vector-db                │  │  │
│  │  │                                                │  │      mountPath: /mnt/vector-db                │  │  │
│  │  │  ─────────────────────────────                 │  │    embedding:                                  │  │  │
│  │  │  Creates:                                      │  │      local:                                    │  │  │
│  │  │  ├─ Deployment (vLLM inference)                │  │        modelID: BAAI/bge-small-en-v1.5        │  │  │
│  │  │  ├─ Service (ClusterIP :80)                    │  │    inferenceService:                           │  │  │
│  │  │  └─ Machine CR → GPU node                      │  │      url: http://workspace-phi-4-mini-        │  │  │
│  │  │                                                │  │       instruct.default.svc.cluster.local       │  │  │
│  │  │  Service DNS:                                  │  │       /v1/completions                          │  │  │
│  │  │  workspace-phi-4-mini-instruct                 │  │      contextWindowSize: 512                   │  │  │
│  │  │   .default.svc.cluster.local                   │  │                                               │  │  │
│  │  └────────────────────────────────────────────────┘  │  ─────────────────────────────                 │  │  │
│  │                                                       │  Creates:                                     │  │  │
│  │                                                       │  ├─ Deployment (RAGService)                   │  │  │
│  │                                                       │  ├─ Service (ClusterIP :80)                   │  │  │
│  │                                                       │  └─ Machine CR → GPU node                     │  │  │
│  │                                                       └───────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ══════════════════════════════════════════════════════════════════════════════════════════════════════════    │
│  GENERATED K8s RESOURCES IN DEFAULT NAMESPACE (created automatically by controllers)                         │
│  ══════════════════════════════════════════════════════════════════════════════════════════════════════════    │
│                                                                                                               │
│  ┌── GPU NODE 1 (auto-provisioned for Workspace) ────────────────────────────────────────────────────────┐  │
│  │  VM: Standard_NV36ads_A10_v5  │  GPU: 1x NVIDIA A10, 24GB  │  Labels: apps=phi-4-mini-instruct       │  │
│  │                                                                                                         │  │
│  │  ┌── Deployment: workspace-phi-4-mini-instruct ──────────────────────────────────────────────────┐     │  │
│  │  │  Replicas: 1   |  Strategy: RollingUpdate                                                      │     │  │
│  │  │                                                                                                 │     │  │
│  │  │  ┌── Pod: workspace-phi-4-mini-instruct-xxxxxxxxx-xxxxx ──────────────────────────────────┐    │     │  │
│  │  │  │                                                                                         │    │     │  │
│  │  │  │  initContainer: model-weights-downloader                                                │    │     │  │
│  │  │  │  ├─ Downloads: microsoft/phi-4-mini-instruct from HuggingFace / MCR                    │    │     │  │
│  │  │  │  └─ Writes to: /workspace/vllm/weights                                                 │    │     │  │
│  │  │  │                                                                                         │    │     │  │
│  │  │  │  container: vllm-inference                                                              │    │     │  │
│  │  │  │  ├─ Image: mcr.microsoft.com/kaito/kaito-vllm:latest                                   │    │     │  │
│  │  │  │  ├─ Port: 5000                                                                          │    │     │  │
│  │  │  │  ├─ GPU: nvidia.com/gpu=1                                                               │    │     │  │
│  │  │  │  ├─ Args: --model /workspace/vllm/weights --gpu-memory-utilization 0.85                │    │     │  │
│  │  │  │  └─ Probes: liveness+readiness → GET /health                                           │    │     │  │
│  │  │  │                                                                                         │    │     │  │
│  │  │  │  Exposes:                                                                               │    │     │  │
│  │  │  │  ├─ POST /v1/chat/completions   (OpenAI-compatible chat)                                │    │     │  │
│  │  │  │  ├─ POST /v1/completions        (OpenAI-compatible completions)                         │    │     │  │
│  │  │  │  ├─ GET  /v1/models             (list models → {"id":"phi-4-mini-instruct",...})        │    │     │  │
│  │  │  │  ├─ GET  /health                (health check)                                          │    │     │  │
│  │  │  │  └─ GET  /metrics               (Prometheus: vllm_* metrics)                            │    │     │  │
│  │  │  └─────────────────────────────────────────────────────────────────────────────────────────┘    │     │  │
│  │  └────────────────────────────────────────────────────────────────────────────────────────────────┘     │  │
│  │                                                                                                         │  │
│  │  ┌── Service: workspace-phi-4-mini-instruct ──┐                                                        │  │
│  │  │  Type: ClusterIP  │  Port: 80 → 5000       │                                                        │  │
│  │  │  Selector: apps=phi-4-mini-instruct         │                                                        │  │
│  │  │  DNS: workspace-phi-4-mini-instruct.default.svc.cluster.local                                       │  │
│  │  └─────────────────────────────────────────────┘                                                        │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                        │                                                                                      │
│                        │  inferenceService.url points here                                                    │
│                        │  http://workspace-phi-4-mini-instruct.default.svc.cluster.local/v1/completions      │
│                        ▼                                                                                      │
│  ┌── GPU NODE 2 (auto-provisioned for RAGEngine) ────────────────────────────────────────────────────────┐  │
│  │  VM: Standard_NC4as_T4_v3  │  GPU: 1x NVIDIA T4, 16GB  │  Labels: apps=ragengine-phi4                │  │
│  │                                                                                                         │  │
│  │  ┌── Deployment: rag-phi4 (RAGService) ──────────────────────────────────────────────────────────┐     │  │
│  │  │  Replicas: 1   |  Created by: RAGEngine controller                                             │     │  │
│  │  │                                                                                                 │     │  │
│  │  │  ┌── Pod: rag-phi4-xxxxxxxxx-xxxxx ───────────────────────────────────────────────────────┐    │     │  │
│  │  │  │                                                                                         │    │     │  │
│  │  │  │  container: rag-service                                                                 │    │     │  │
│  │  │  │  ├─ Stack: Python + FastAPI + LlamaIndex + FAISS + Sentence-Transformers                │    │     │  │
│  │  │  │  ├─ Embedding: BAAI/bge-small-en-v1.5 (loaded on GPU)                                  │    │     │  │
│  │  │  │  ├─ Vector DB: FAISS in-memory (persisted to PVC via PreStop hook)                      │    │     │  │
│  │  │  │  ├─ Orchestrator: LlamaIndex (query routing, prompt building)                           │    │     │  │
│  │  │  │  ├─ Port: 5000                                                                          │    │     │  │
│  │  │  │  ├─ GPU: nvidia.com/gpu=1 (for local embedding)                                        │    │     │  │
│  │  │  │  └─ VolumeMounts:                                                                       │    │     │  │
│  │  │  │       /mnt/vector-db → PVC: pvc-ragengine-vector-db (Azure Disk, 50Gi)                 │    │     │  │
│  │  │  │                                                                                         │    │     │  │
│  │  │  │  ┌── RAGService API Endpoints ─────────────────────────────────────────────────────┐   │    │     │  │
│  │  │  │  │                                                                                  │   │    │     │  │
│  │  │  │  │  INDEX MANAGEMENT:                                                               │   │    │     │  │
│  │  │  │  │  ├─ POST   /index                               Create index + add documents    │   │    │     │  │
│  │  │  │  │  │         Body: {"index_name":"...", "documents":[{"text":"...", "metadata":{}}]}│   │    │     │  │
│  │  │  │  │  │         → Splits docs into nodes (sentence or code-aware)                     │   │    │     │  │
│  │  │  │  │  │         → Embeds with BAAI/bge-small on GPU                                   │   │    │     │  │
│  │  │  │  │  │         → Indexes into FAISS vector store                                     │   │    │     │  │
│  │  │  │  │  │                                                                               │   │    │     │  │
│  │  │  │  │  ├─ GET    /indexes/{name}/documents            List docs (paginated)            │   │    │     │  │
│  │  │  │  │  │         ?limit=10&offset=0&max_text_length=1000&metadata_filter={}            │   │    │     │  │
│  │  │  │  │  │                                                                               │   │    │     │  │
│  │  │  │  │  ├─ POST   /indexes/{name}/documents            Update existing documents        │   │    │     │  │
│  │  │  │  │  ├─ POST   /indexes/{name}/documents/delete     Delete documents by doc_id       │   │    │     │  │
│  │  │  │  │  └─ DELETE  /indexes/{name}                     Delete entire index              │   │    │     │  │
│  │  │  │  │                                                                                  │   │    │     │  │
│  │  │  │  │  PERSISTENCE:                                                                    │   │    │     │  │
│  │  │  │  │  ├─ POST   /persist/{name}?path=./custom_path   Save index to PVC               │   │    │     │  │
│  │  │  │  │  └─ POST   /load/{name}?path=...&overwrite=false  Load index from PVC           │   │    │     │  │
│  │  │  │  │     (Auto-persist on pod PreStop, auto-load on PostStart; 5 snapshots retained)  │   │    │     │  │
│  │  │  │  │                                                                                  │   │    │     │  │
│  │  │  │  │  RAG-AUGMENTED INFERENCE (OpenAI-compatible):                                    │   │    │     │  │
│  │  │  │  │  └─ POST   /v1/chat/completions                                                 │   │    │     │  │
│  │  │  │  │             Body: {                                                              │   │    │     │  │
│  │  │  │  │               "index_name": "my_docs",        ← triggers RAG pipeline            │   │    │     │  │
│  │  │  │  │               "model": "phi-4-mini-instruct",                                    │   │    │     │  │
│  │  │  │  │               "messages": [{"role":"user","content":"What is our policy?"}],     │   │    │     │  │
│  │  │  │  │               "temperature": 0.7,                                                │   │    │     │  │
│  │  │  │  │               "max_tokens": 2048,                                                │   │    │     │  │
│  │  │  │  │               "context_token_ratio": 0.5      ← % tokens for RAG context        │   │    │     │  │
│  │  │  │  │             }                                                                    │   │    │     │  │
│  │  │  │  │             Response includes "source_nodes" with doc_id, score, metadata        │   │    │     │  │
│  │  │  │  │                                                                                  │   │    │     │  │
│  │  │  │  │  BYPASS: If no index_name, or tools/functions present → direct LLM passthrough   │   │    │     │  │
│  │  │  │  └──────────────────────────────────────────────────────────────────────────────────┘   │    │     │  │
│  │  │  └─────────────────────────────────────────────────────────────────────────────────────────┘    │     │  │
│  │  └────────────────────────────────────────────────────────────────────────────────────────────────┘     │  │
│  │                                                                                                         │  │
│  │  ┌── Service: rag-phi4 ────────────────────────┐  ┌── PVC: pvc-ragengine-vector-db ──────────────┐     │  │
│  │  │  Type: ClusterIP  │  Port: 80 → 5000        │  │  StorageClass: managed-csi-premium            │     │  │
│  │  │  Selector: apps=ragengine-phi4              │  │  AccessMode: ReadWriteOnce                    │     │  │
│  │  │  DNS: rag-phi4.default.svc.cluster.local    │  │  Size: 50Gi (Azure Managed Disk)              │     │  │
│  │  └──────────────────────────────────────────────┘  │  Mounted at: /mnt/vector-db                  │     │  │
│  │                                                     │  Purpose: Persist FAISS indexes across       │     │  │
│  │                                                     │  pod restarts (5 snapshots retained)         │     │  │
│  │                                                     └─────────────────────────────────────────────┘     │  │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── kubectl get all — Expected Resources ───────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  $ kubectl get all,workspace,ragengine,pvc                                                             │  │
│  │                                                                                                        │  │
│  │  NAME                                                    READY   STATUS    AGE                         │  │
│  │  pod/workspace-phi-4-mini-instruct-xxxxxxxxx-xxxxx       1/1     Running   4h                          │  │
│  │  pod/rag-phi4-xxxxxxxxx-xxxxx                            1/1     Running   3h                          │  │
│  │                                                                                                        │  │
│  │  NAME                                     TYPE        CLUSTER-IP     PORT(S)   AGE                     │  │
│  │  svc/workspace-phi-4-mini-instruct        ClusterIP   10.0.x.x       80/TCP    4h                     │  │
│  │  svc/rag-phi4                             ClusterIP   10.0.x.x       80/TCP    3h                     │  │
│  │                                                                                                        │  │
│  │  NAME                                                    READY   UP-TO-DATE   AGE                      │  │
│  │  deploy/workspace-phi-4-mini-instruct                    1/1     1            4h                       │  │
│  │  deploy/rag-phi4                                         1/1     1            3h                       │  │
│  │                                                                                                        │  │
│  │  NAME                                     INSTANCE                RESOURCEREADY  INFERENCEREADY        │  │
│  │  workspace/workspace-phi-4-mini-instruct  Standard_NV36ads_A10   True           True                  │  │
│  │                                                                                                        │  │
│  │  NAME                           STATUS    AGE                                                          │  │
│  │  ragengine/rag-phi4             Ready     3h                                                           │  │
│  │                                                                                                        │  │
│  │  NAME                                STATUS   VOLUME        CAPACITY   STORAGECLASS                    │  │
│  │  pvc/pvc-ragengine-vector-db         Bound    pv-xxxxx      50Gi       managed-csi-premium             │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### RAG Internal Data Flow (inside K8s cluster)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                               │
│  User / Client (Streamlit, API, Headlamp)                                                                     │
│       │                                                                                                       │
│       │  kubectl port-forward svc/rag-phi4 8080:80                                                            │
│       │  POST http://localhost:8080/v1/chat/completions                                                       │
│       │  {"index_name":"company_docs", "messages":[...], "context_token_ratio":0.5}                           │
│       ▼                                                                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐ │
│  │  Service: rag-phi4 (ClusterIP) ─────────────────────────────────────────────────────────────────────── │ │
│  │       │                                                                                                 │ │
│  │       ▼                                                                                                 │ │
│  │  Pod: rag-phi4-xxxxx  (RAGService on GPU Node 2)                                                       │ │
│  │  ┌──────────────────────────────────────────────────────────────────────────────────────────────────┐  │ │
│  │  │                                                                                                   │  │ │
│  │  │  ┌─ STEP 1: Embed Query ─────────────────────┐                                                   │  │ │
│  │  │  │  Model: BAAI/bge-small-en-v1.5 (on T4 GPU)│                                                   │  │ │
│  │  │  │  Input: "What is our refund policy?"       │                                                   │  │ │
│  │  │  │  Output: [0.012, 0.445, -0.231, ...] 384d  │                                                   │  │ │
│  │  │  └───────────────────────────┬────────────────┘                                                   │  │ │
│  │  │                              │                                                                     │  │ │
│  │  │                              ▼                                                                     │  │ │
│  │  │  ┌─ STEP 2: FAISS Vector Search ─────────────┐                                                   │  │ │
│  │  │  │  Index: "company_docs"                     │                                                   │  │ │
│  │  │  │  Algorithm: Approximate Nearest Neighbor    │                                                   │  │ │
│  │  │  │  Returns: Top-K document nodes with scores │                                                   │  │ │
│  │  │  │  Source: /mnt/vector-db (PVC-backed)       │                                                   │  │ │
│  │  │  │                                            │                                                   │  │ │
│  │  │  │  Results:                                   │                                                   │  │ │
│  │  │  │  ├─ node_1: "Refund policy: 30 days..." (score: 0.95)                                          │  │ │
│  │  │  │  ├─ node_2: "Returns must include..."   (score: 0.88)                                          │  │ │
│  │  │  │  └─ node_3: "Exceptions apply to..."    (score: 0.82)                                          │  │ │
│  │  │  └───────────────────────────┬────────────────┘                                                   │  │ │
│  │  │                              │                                                                     │  │ │
│  │  │                              ▼                                                                     │  │ │
│  │  │  ┌─ STEP 3: LlamaIndex Prompt Augmentation ──┐                                                   │  │ │
│  │  │  │  Builds augmented prompt:                   │                                                   │  │ │
│  │  │  │  ┌────────────────────────────────────────┐ │                                                   │  │ │
│  │  │  │  │ System: Answer based on context below. │ │                                                   │  │ │
│  │  │  │  │ Context:                                │ │                                                   │  │ │
│  │  │  │  │   "Refund policy: 30 days..."          │ │                                                   │  │ │
│  │  │  │  │   "Returns must include..."            │ │                                                   │  │ │
│  │  │  │  │   "Exceptions apply to..."             │ │                                                   │  │ │
│  │  │  │  │ User: What is our refund policy?       │ │                                                   │  │ │
│  │  │  │  └────────────────────────────────────────┘ │                                                   │  │ │
│  │  │  │  context_token_ratio: 0.5                   │                                                   │  │ │
│  │  │  │  → ~50% of max_tokens filled with context  │                                                   │  │ │
│  │  │  └───────────────────────────┬────────────────┘                                                   │  │ │
│  │  │                              │                                                                     │  │ │
│  │  └──────────────────────────────┼────────────────────────────────────────────────────────────────────┘  │ │
│  │                                 │  HTTP call to Workspace                                               │ │
│  └─────────────────────────────────┼───────────────────────────────────────────────────────────────────────┘ │
│                                    │                                                                          │
│                                    │  POST http://workspace-phi-4-mini-instruct.default.svc.cluster.local    │
│                                    │       /v1/completions                                                     │
│                                    ▼                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐ │
│  │  Service: workspace-phi-4-mini-instruct (ClusterIP)                                                     │ │
│  │       │                                                                                                  │ │
│  │       ▼                                                                                                  │ │
│  │  Pod: workspace-phi-4-mini-instruct-xxxxx  (vLLM on GPU Node 1, A10 24GB)                               │ │
│  │  ┌──────────────────────────────────────────────────────────────────────────────────────────────────┐   │ │
│  │  │                                                                                                   │   │ │
│  │  │  ┌─ STEP 4: LLM Inference (vLLM) ───────────────────────────────────────────────────────────┐   │   │ │
│  │  │  │  Model: phi-4-mini-instruct (3.8B params, loaded in GPU VRAM)                              │   │   │ │
│  │  │  │  Input: Augmented prompt with RAG context                                                   │   │   │ │
│  │  │  │  Output: "Our refund policy allows returns within 30 days of purchase.                      │   │   │ │
│  │  │  │           Returns must include original receipt. Exceptions apply to                         │   │   │ │
│  │  │  │           clearance items and digital downloads."                                            │   │   │ │
│  │  │  │                                                                                             │   │   │ │
│  │  │  │  Returned to RAGService → appended with source_nodes → returned to user                    │   │   │ │
│  │  │  └─────────────────────────────────────────────────────────────────────────────────────────────┘   │   │ │
│  │  └──────────────────────────────────────────────────────────────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                                               │
│  Response to User:                                                                                            │
│  {                                                                                                            │
│    "choices": [{"message":{"content":"Our refund policy allows returns within 30 days..."}}],                │
│    "source_nodes": [                                                                                          │
│      {"doc_id":"abc123", "node_id":"...", "text":"Refund policy: 30 days...", "score":0.95},                 │
│      {"doc_id":"def456", "node_id":"...", "text":"Returns must include...", "score":0.88}                    │
│    ]                                                                                                          │
│  }                                                                                                            │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. KAITO RAGEngine CRD — Official Spec & K8s Resource Mapping

> Source: [KAITO RAG Docs](https://kaito-project.github.io/kaito/docs/rag)
>
> The RAGEngine CRD is **v1alpha1**. Install via separate Helm chart:
> `helm install kaito-ragengine kaito/ragengine -n kaito-ragengine --create-namespace`

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                               │
│                       RAGEngine CRD — Official YAML Spec (v1alpha1)                                           │
│                                                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  apiVersion: kaito.sh/v1alpha1                                                                         │  │
│  │  kind: RAGEngine                                                                                       │  │
│  │  metadata:                                                                                             │  │
│  │    name: rag-phi4                                                                                      │  │
│  │    namespace: default                                                                                  │  │
│  │  spec:                                                                                                 │  │
│  │    compute:                                       ◄── GPU node for RAGService container                │  │
│  │      instanceType: "Standard_NC4as_T4_v3"              (auto-provisioned if no matching node)          │  │
│  │      count: 1                                                                                          │  │
│  │      labelSelector:                                                                                    │  │
│  │        matchLabels:                                                                                    │  │
│  │          apps: ragengine-phi4                                                                          │  │
│  │                                                                                                        │  │
│  │    embedding:                                     ◄── How documents & queries are embedded              │  │
│  │      local:                                            Option A: LOCAL (runs on same GPU pod)           │  │
│  │        modelID: "BAAI/bge-small-en-v1.5"               384-dim vectors, ~130M params                   │  │
│  │                                                                                                        │  │
│  │    # embedding:                                        Option B: REMOTE (call external API)             │  │
│  │    #   remote:                                                                                         │  │
│  │    #     url: "https://<openai-endpoint>.openai.azure.com/..."                                         │  │
│  │    #     accessSecret: "embedding-api-key"                                                             │  │
│  │                                                                                                        │  │
│  │    inferenceService:                              ◄── LLM backend (KAITO Workspace or external)        │  │
│  │      url: "http://workspace-phi-4-mini-instruct.default.svc.cluster.local/v1/completions"              │  │
│  │      contextWindowSize: 512                            Max context tokens for RAG chunks                │  │
│  │                                                                                                        │  │
│  │    storage:                                       ◄── Optional PVC for FAISS persistence               │  │
│  │      persistentVolumeClaim: pvc-ragengine-vector-db                                                    │  │
│  │      mountPath: /mnt/vector-db                         (auto-persist PreStop, auto-load PostStart)     │  │
│  │                                                        (5 rolling snapshots retained)                   │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── CRD → K8s Resource Mapping ─────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  When you apply the RAGEngine CR above, the RAGEngine controller reconciles and creates:               │  │
│  │                                                                                                        │  │
│  │  RAGEngine CR                                                                                          │  │
│  │      │                                                                                                 │  │
│  │      ├──► Machine CR                          GPU node auto-provisioning (if needed)                   │  │
│  │      │    └─ instance: Standard_NC4as_T4_v3   → Azure provisions VM → joins AKS as node               │  │
│  │      │                                                                                                 │  │
│  │      ├──► Deployment: rag-phi4                                                                         │  │
│  │      │    ├─ replicas: 1                                                                               │  │
│  │      │    ├─ nodeSelector: apps=ragengine-phi4                                                         │  │
│  │      │    └─ template:                                                                                 │  │
│  │      │       └─ container: rag-service                                                                 │  │
│  │      │          ├─ image: mcr.microsoft.com/kaito/kaito-rag:latest                                     │  │
│  │      │          ├─ port: 5000                                                                          │  │
│  │      │          ├─ resources: nvidia.com/gpu=1                                                         │  │
│  │      │          ├─ env:                                                                                │  │
│  │      │          │   EMBEDDING_MODEL=BAAI/bge-small-en-v1.5                                             │  │
│  │      │          │   INFERENCE_URL=http://workspace-phi-4-mini-instruct.../v1/completions               │  │
│  │      │          │   CONTEXT_WINDOW_SIZE=512                                                             │  │
│  │      │          ├─ volumeMounts: /mnt/vector-db → PVC                                                  │  │
│  │      │          └─ lifecycle:                                                                           │  │
│  │      │              preStop:  persist FAISS indexes to PVC                                              │  │
│  │      │              postStart: load FAISS indexes from PVC                                              │  │
│  │      │                                                                                                 │  │
│  │      ├──► Service: rag-phi4                                                                            │  │
│  │      │    ├─ type: ClusterIP                                                                           │  │
│  │      │    ├─ port: 80 → targetPort: 5000                                                               │  │
│  │      │    └─ selector: apps=ragengine-phi4                                                             │  │
│  │      │                                                                                                 │  │
│  │      └──► PVC: pvc-ragengine-vector-db (if spec.storage defined)                                      │  │
│  │           ├─ storageClass: managed-csi-premium                                                         │  │
│  │           ├─ accessMode: ReadWriteOnce                                                                 │  │
│  │           └─ capacity: 50Gi                                                                            │  │
│  │                                                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── RAGEngine API Summary Table ────────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  Method  │  Endpoint                                │  Purpose                                         │  │
│  │  ────────┼──────────────────────────────────────────┼────────────────────────────────────────────────  │  │
│  │  POST    │  /index                                  │  Create index + add documents                    │  │
│  │  GET     │  /indexes/{name}/documents               │  List docs (paginated, with filters)             │  │
│  │  POST    │  /indexes/{name}/documents               │  Update existing documents                       │  │
│  │  POST    │  /indexes/{name}/documents/delete        │  Delete docs by doc_id list                      │  │
│  │  DELETE  │  /indexes/{name}                         │  Delete entire index                             │  │
│  │  POST    │  /persist/{name}                         │  Save index snapshot to PVC                      │  │
│  │  POST    │  /load/{name}                            │  Load index from PVC snapshot                    │  │
│  │  POST    │  /v1/chat/completions                    │  RAG-augmented chat (OpenAI-compatible)          │  │
│  │          │    (with index_name → RAG)               │    response includes source_nodes                │  │
│  │          │    (without index_name → LLM passthrough)│    direct inference, no retrieval                │  │
│  │                                                                                                        │  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                               │
│  ┌── End-to-End Deployment Commands ─────────────────────────────────────────────────────────────────────┐  │
│  │                                                                                                        │  │
│  │  # 1. Install RAGEngine controller                                                                     │  │
│  │  helm install kaito-ragengine kaito/ragengine -n kaito-ragengine --create-namespace                    │  │
│  │                                                                                                        │  │
│  │  # 2. Create PVC for persistence (optional but recommended)                                            │  │
│  │  kubectl apply -f - <<EOF                                                                              │  │
│  │  apiVersion: v1                                                                                        │  │
│  │  kind: PersistentVolumeClaim                                                                           │  │
│  │  metadata:                                                                                             │  │
│  │    name: pvc-ragengine-vector-db                                                                       │  │
│  │  spec:                                                                                                 │  │
│  │    accessModes: [ReadWriteOnce]                                                                        │  │
│  │    storageClassName: managed-csi-premium                                                               │  │
│  │    resources:                                                                                          │  │
│  │      requests:                                                                                         │  │
│  │        storage: 50Gi                                                                                   │  │
│  │  EOF                                                                                                   │  │
│  │                                                                                                        │  │
│  │  # 3. Apply RAGEngine CR                                                                               │  │
│  │  kubectl apply -f ragengine-phi4.yaml                                                                  │  │
│  │                                                                                                        │  │
│  │  # 4. Watch for GPU provisioning + pod readiness                                                       │  │
│  │  kubectl get ragengine rag-phi4 -w                                                                     │  │
│  │  kubectl get pods -l apps=ragengine-phi4 -w                                                            │  │
│  │                                                                                                        │  │
│  │  # 5. Index your documents                                                                             │  │
│  │  kubectl port-forward svc/rag-phi4 8080:80                                                             │  │
│  │  curl -X POST http://localhost:8080/index \                                                            │  │
│  │    -H "Content-Type: application/json" \                                                               │  │
│  │    -d '{"index_name":"my_kb","documents":[{"text":"Company policy: ...","metadata":{"src":"policy"}}]}'│  │
│  │                                                                                                        │  │
│  │  # 6. Query with RAG                                                                                   │  │
│  │  curl -X POST http://localhost:8080/v1/chat/completions \                                              │  │
│  │    -H "Content-Type: application/json" \                                                               │  │
│  │    -d '{"index_name":"my_kb","model":"phi-4","messages":[{"role":"user","content":"What is policy?"}]}'│  │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. End-to-End Production Architecture (Hub-Spoke + K8s + RAG Combined)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                                               │
│  INTERNET / ON-PREM USERS                                                                                     │
│       │                                                                                                       │
│       │  HTTPS                                                                                                │
│       ▼                                                                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐                                         │
│  │  Azure Front Door / Application Gateway (WAF)                    │                                         │
│  │  - SSL termination                                               │                                         │
│  │  - DDoS protection                                               │                                         │
│  │  - Rate limiting                                                 │                                         │
│  └──────────────────────────────┬───────────────────────────────────┘                                         │
│                                  │                                                                             │
│                                  ▼                                                                             │
│  ┌──────────────────── HUB VNET ────────────────────────────────────────────────────────────────────────────┐ │
│  │                                                                                                           │ │
│  │   Azure Firewall ◄──── Egress Rules: HuggingFace, MCR, PyPI                                              │ │
│  │   Azure Bastion  ◄──── Secure admin access                                                               │ │
│  │   VPN Gateway    ◄──── On-premises connectivity                                                           │ │
│  │   DNS Resolver   ◄──── Private DNS zones                                                                  │ │
│  │   Log Analytics  ◄──── Centralized logging                                                                │ │
│  │                                                                                                           │ │
│  └──────┬────────────────────────────────┬───────────────────────────────────┬───────────────────────────────┘ │
│         │ Peering                        │ Peering                           │ Peering                         │
│         ▼                                ▼                                   ▼                                 │
│  ┌─ SPOKE 1: AKS ──────────┐  ┌─ SPOKE 2: DATA ──────────────┐  ┌─ SPOKE 3: APP ───────────────┐           │
│  │                          │  │                               │  │                               │           │
│  │  AKS Cluster             │  │  Azure AI Search (Vectors)   │  │  Azure API Mgmt              │           │
│  │  ├─ System Pool          │  │         ▲                     │  │  ├─ /v1/chat  → AKS           │           │
│  │  │  └─ KAITO Controller  │  │         │ Store Embeddings    │  │  ├─ /v1/rag   → AKS           │           │
│  │  │                       │  │         │                     │  │  └─ Auth, Rate Limit, Logs    │           │
│  │  ├─ GPU Pool 1           │  │  Azure Cosmos DB             │  │                               │           │
│  │  │  └─ Workspace:        │  │  ├─ Chat history             │  │  Streamlit / React Frontend   │           │
│  │  │     phi-4-mini        │  │  └─ User sessions            │  │  ├─ Chat UI                   │           │
│  │  │     (Inference)       │  │                               │  │  ├─ Doc upload               │           │
│  │  │                       │  │  Azure Blob Storage           │  │  └─ Admin panel              │           │
│  │  ├─ GPU Pool 2 (opt.)    │  │  └─ Source documents          │  │                               │           │
│  │  │  └─ RAGEngine:        │  │                               │  │                               │           │
│  │  │     rag-phi4          │  │  Azure OpenAI                 │  │                               │           │
│  │  │     (Embed + Index)   │  │  └─ text-embedding-ada-002    │  │                               │           │
│  │  │                       │  │     (Embedding generation)    │  │                               │           │
│  │  ├─ Headlamp Pod         │  │                               │  │                               │           │
│  │  └─ Monitoring Stack     │  │                               │  │                               │           │
│  │     ├─ Prometheus        │  │                               │  │                               │           │
│  │     └─ ServiceMonitor    │  │                               │  │                               │           │
│  └──────────────────────────┘  └───────────────────────────────┘  └───────────────────────────────┘           │
│                                                                                                               │
│  ┌── SECURITY & IDENTITY ────────────────────────────────────────────────────────────────────────────────┐   │
│  │                                                                                                        │   │
│  │  Microsoft Entra ID                                                                                    │   │
│  │  ├─ Managed Identity (AKS ─► ACR, Key Vault, Storage)                                                │   │
│  │  ├─ Workload Identity  (Pods ─► Azure AI Search, Cosmos DB, OpenAI)                                   │   │
│  │  ├─ OIDC Issuer        (Federated token exchange)                                                     │   │
│  │  └─ RBAC               (Azure roles + K8s ClusterRoles)                                               │   │
│  │                                                                                                        │   │
│  │  Network Security                                                                                      │   │
│  │  ├─ Private Endpoints   (ACR, AI Search, Cosmos DB, Storage, Key Vault)                               │   │
│  │  ├─ Network Policies    (Calico/Azure NPM - namespace isolation)                                      │   │
│  │  ├─ Azure Firewall      (Egress filtering - allow only needed FQDNs)                                  │   │
│  │  └─ NSGs                (Subnet-level traffic control)                                                │   │
│  │                                                                                                        │   │
│  │  Secrets Management                                                                                    │   │
│  │  ├─ Azure Key Vault      (HF tokens, API keys, connection strings)                                   │   │
│  │  ├─ CSI Secrets Driver    (Mount Key Vault secrets as K8s volumes)                                    │   │
│  │  └─ K8s Secrets           (hf-token for gated model access)                                           │   │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                                               │
│  ┌── OBSERVABILITY ──────────────────────────────────────────────────────────────────────────────────────┐   │
│  │                                                                                                        │   │
│  │  Azure Monitor                               Grafana Dashboard                                         │   │
│  │  ├─ Managed Prometheus ◄── ServiceMonitor     ├─ vLLM Metrics                                         │   │
│  │  │  (vLLM metrics scraping)                   │  ├─ Requests/sec                                      │   │
│  │  ├─ Container Insights                        │  ├─ Tokens/sec                                        │   │
│  │  │  (Pod CPU/Memory/GPU)                      │  ├─ GPU utilization                                   │   │
│  │  └─ Log Analytics                             │  ├─ KV cache usage                                    │   │
│  │     (Audit logs, diagnostics)                 │  └─ Queue depth                                       │   │
│  │                                                └─ Cluster Health                                       │   │
│  └────────────────────────────────────────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Request Flow Sequence — RAGEngine API (Official Endpoints)

```
  User (Streamlit/curl)        svc/rag-phi4           Pod: rag-phi4           FAISS          svc/workspace-phi4      Pod: workspace-phi4
       │                        (ClusterIP)         (RAGService on T4)      (in-memory)        (ClusterIP)           (vLLM on A10)
       │                            │                      │                    │                    │                     │
       │  ══════════════════ INDEX DOCUMENTS (one-time) ════════════════════════════════                                   │
       │                            │                      │                    │                    │                     │
       │  POST /index               │                      │                    │                    │                     │
       │  {"index_name":"my_kb",    │                      │                    │                    │                     │
       │   "documents":[            │                      │                    │                    │                     │
       │     {"text":"Policy...",   │                      │                    │                    │                     │
       │      "metadata":{...}}     │                      │                    │                    │                     │
       │   ]}                       │                      │                    │                    │                     │
       │───────────────────────────►│─────────────────────►│                    │                    │                     │
       │                            │                      │  Sentence split    │                    │                     │
       │                            │                      │  Embed each node   │                    │                     │
       │                            │                      │  (bge-small, GPU)  │                    │                     │
       │                            │                      │───────────────────►│                    │                     │
       │                            │                      │  Store vectors     │                    │                     │
       │                            │   {"index_name":     │◄───────────────────│                    │                     │
       │  200 OK                    │    "my_kb",          │                    │                    │                     │
       │  {"index_name":"my_kb",    │    "documents":N}    │                    │                    │                     │
       │   "documents":N}           │◄─────────────────────│                    │                    │                     │
       │◄───────────────────────────│                      │                    │                    │                     │
       │                            │                      │                    │                    │                     │
       │  ══════════════════ RAG QUERY (repeated) ═════════════════════════════════                                        │
       │                            │                      │                    │                    │                     │
       │  POST /v1/chat/completions │                      │                    │                    │                     │
       │  {"index_name":"my_kb",    │                      │                    │                    │                     │
       │   "model":"phi-4",         │                      │                    │                    │                     │
       │   "messages":[{"role":     │                      │                    │                    │                     │
       │    "user","content":       │                      │                    │                    │                     │
       │    "What is refund?"}],    │                      │                    │                    │                     │
       │   "context_token_ratio":   │                      │                    │                    │                     │
       │    0.5}                    │                      │                    │                    │                     │
       │───────────────────────────►│─────────────────────►│                    │                    │                     │
       │                            │                      │                    │                    │                     │
       │                            │                      │  1. Embed query    │                    │                     │
       │                            │                      │  (bge-small, GPU)  │                    │                     │
       │                            │                      │                    │                    │                     │
       │                            │                      │  2. Vector search  │                    │                     │
       │                            │                      │───────────────────►│                    │                     │
       │                            │                      │  Top-K nodes       │                    │                     │
       │                            │                      │  + scores          │                    │                     │
       │                            │                      │◄───────────────────│                    │                     │
       │                            │                      │                    │                    │                     │
       │                            │                      │  3. LlamaIndex builds augmented prompt                       │
       │                            │                      │  context_token_ratio=0.5 → fill 50% tokens with RAG context  │
       │                            │                      │                    │                    │                     │
       │                            │                      │  4. POST /v1/completions                │                     │
       │                            │                      │  {"prompt":"Context: [chunks]\nQ: refund?"}                   │
       │                            │                      │───────────────────────────────────────►│────────────────────►│
       │                            │                      │                    │                    │                     │
       │                            │                      │                    │                    │  vLLM inference     │
       │                            │                      │                    │                    │  phi-4 on A10 GPU   │
       │                            │                      │                    │                    │                     │
       │                            │                      │  5. LLM response   │                    │                     │
       │                            │                      │◄──────────────────────────────────────│◄────────────────────│
       │                            │                      │                    │                    │                     │
       │                            │  6. Append source_nodes to response       │                    │                     │
       │  200 OK                    │  {"choices":[...],   │                    │                    │                     │
       │  {"choices":[{"message":   │   "source_nodes":    │                    │                    │                     │
       │    {"content":"Refund      │   [{"doc_id":"...",  │                    │                    │                     │
       │     allows 30 days..."}}], │    "score":0.95,     │                    │                    │                     │
       │   "source_nodes":[...]}    │    "text":"..."}]}   │                    │                    │                     │
       │◄───────────────────────────│◄─────────────────────│                    │                    │                     │
       │                            │                      │                    │                    │                     │
       │  ══════════════════ PERSISTENCE (optional) ═══════════════════════════                                            │
       │                            │                      │                    │                    │                     │
       │  POST /persist/my_kb       │                      │                    │                    │                     │
       │───────────────────────────►│─────────────────────►│  Save FAISS →     │                    │                     │
       │                            │                      │  /mnt/vector-db/   │                    │                     │
       │  200 OK                    │                      │  (PVC snapshot)    │                    │                     │
       │◄───────────────────────────│◄─────────────────────│                    │                    │                     │
       │                            │                      │                    │                    │                     │
```

---

## 8. File-to-Architecture Mapping

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│  REPO FILES                           │  ARCHITECTURE COMPONENT                                               │
├───────────────────────────────────────┼───────────────────────────────────────────────────────────────────────┤
│                                       │                                                                       │
│  demokaitoheadlamp.sh                │  Single-node AKS + KAITO + Headlamp setup                             │
│  ├─ step4_create_aks()               │  ─► AKS Cluster creation (Spoke 1)                                    │
│  ├─ step6_install_headlamp()         │  ─► Headlamp UI deployment                                            │
│  └─ step7_deploy_workspace()         │  ─► KAITO Workspace (phi-4) on GPU node                               │
│                                       │                                                                       │
│  multinodedemokaito.sh               │  Multi-node AKS + KAITO + llm-d setup                                 │
│  ├─ step4_create_aks()               │  ─► 3x GPU node cluster creation                                      │
│  ├─ step7_deploy_workspace()         │  ─► KAITO Workspace (gpt-oss-20b, count:3)                            │
│  └─ step8_deploy_llmd()              │  ─► llm-d Gateway API Inference Extension                              │
│                                       │                                                                       │
│  workspace-phi4.yaml                 │  KAITO CRD → single A10 GPU → vLLM Pod → phi-4-mini-instruct         │
│  workspace-llama31.yaml              │  KAITO CRD → single A10 GPU → vLLM Pod → llama-3.1-8b (gated)       │
│  workspace-gpt-oss-20b-multinode.yaml│  KAITO CRD → 3x A10 GPUs → multi-node gpt-oss-20b                   │
│                                       │                                                                       │
│  llmd-inference-pool.yaml            │  InferencePool CRD → cache-aware routing to KAITO service             │
│  llmd-inference-model.yaml           │  InferenceModel CRD → model registration for pool                    │
│  llmd-gateway.yaml                   │  Gateway + HTTPRoute → external access via llm-d                      │
│                                       │                                                                       │
│  servicemonitor.yaml                 │  ServiceMonitor → Prometheus scraping of vLLM /metrics                │
│  streamlit_app.py                    │  Streamlit chat UI → POST /v1/chat/completions via port-forward       │
│  test.http                           │  REST Client test file → validate inference endpoints                 │
│  test-multinode.sh                   │  Automated test script → workspace status + inference validation      │
│                                       │                                                                       │
│  demo-env.sh                         │  Environment vars for single-node demo                                 │
│  multinode-demo-env.sh               │  Environment vars for multi-node demo                                  │
└───────────────────────────────────────┴───────────────────────────────────────────────────────────────────────┘
```

---

## 9. Technology Stack Summary

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  LAYER              │  TECHNOLOGY                │  PURPOSE                  │
├─────────────────────┼────────────────────────────┼───────────────────────────┤
│  Cloud Platform     │  Azure                     │  Infrastructure           │
│  Container Orch.    │  AKS (Kubernetes)          │  Workload scheduling      │
│  AI Operator        │  KAITO                     │  LLM lifecycle mgmt       │
│  Inference Engine   │  vLLM                      │  High-perf LLM serving    │
│  GPU Hardware       │  NVIDIA A10/A100/H100      │  Model computation        │
│  Distribution       │  llm-d                     │  P/D disaggregation       │
│  KV Transfer        │  NIXL                      │  GPU-to-GPU cache         │
│  Gateway            │  Gateway API + Envoy       │  Intelligent routing      │
│  UI Dashboard       │  Headlamp + KAITO Plugin   │  Visual K8s management    │
│  Chat UI            │  Streamlit                 │  Interactive testing       │
│  Monitoring         │  Prometheus + Grafana      │  Metrics & dashboards     │
│  Vector Search      │  Azure AI Search / FAISS   │  RAG retrieval            │
│  Embeddings         │  Azure OpenAI / BGE        │  Document vectorization   │
│  Doc Store          │  Azure Blob / Cosmos DB    │  Raw docs & chat history  │
│  Identity           │  Entra ID + Workload ID    │  Zero-trust auth          │
│  Networking         │  Hub-Spoke VNet Peering    │  Network segmentation     │
│  Security           │  Firewall + Private EP     │  Egress control & PaaS    │
└─────────────────────┴────────────────────────────┴───────────────────────────┘
```
