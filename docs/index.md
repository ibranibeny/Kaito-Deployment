---
title: Home
layout: default
nav_order: 1
---

# KAITO on AKS - Architecture & Deployment Guide
{: .fs-9 }

Deploy AI Models with KAITO and Headlamp on Azure Kubernetes Service (AKS)
{: .fs-6 .fw-300 }

---

## Overview

**KAITO** (Kubernetes AI Toolchain Operator) simplifies AI/ML model deployment on AKS by automating GPU provisioning, model downloading, and inference server setup with a single YAML manifest.

### Key Components

| Component | Purpose |
|-----------|---------|
| **KAITO** | Kubernetes AI Toolchain Operator - automates AI/ML model deployment |
| **Headlamp** | Kubernetes GUI dashboard with KAITO plugin |
| **vLLM** | High-performance inference engine with continuous batching |
| **Azure Monitor** | Prometheus metrics and Grafana dashboards |

---

## High-Level Architecture

```mermaid
graph TB
    subgraph Internet
        Users[/"Users / Clients"/]
    end

    subgraph Azure["Azure Cloud"]
        subgraph Hub["Hub VNet (10.0.0.0/16)"]
            FW[Azure Firewall]
            Bastion[Azure Bastion]
            AppGW[Application Gateway WAF v2]
            Monitor[Azure Monitor / Grafana]
            DNS[Azure DNS Private Resolver]
        end

        subgraph Spoke1["Spoke 1: AKS VNet (10.1.0.0/16)"]
            AKS[AKS Cluster with KAITO]
            ACR[Azure Container Registry]
            KV1[Key Vault]
        end

        subgraph Spoke2["Spoke 2: Data VNet (10.2.0.0/16)"]
            PG[PostgreSQL Flexible Server + pgvector]
            Storage[Azure Storage]
        end

        subgraph Spoke3["Spoke 3: Management VNet (10.3.0.0/16)"]
            KV2[Key Vault - Secrets]
            DNS2[DNS Private Resolver]
            ACR2[ACR Private]
        end

        subgraph Shared["Shared Services"]
            Entra[Microsoft Entra ID]
            Policy[Azure Policy]
            Defender[Microsoft Defender for Cloud]
        end
    end

    Users -->|HTTPS 443| AppGW
    AppGW -->|Backend Pool| AKS
    AKS -->|VNet Peering| Hub
    AKS -->|Private Endpoint| PG
    AKS -->|Private Endpoint| ACR
    AKS -->|Private Endpoint| KV1
    Hub --- Spoke1
    Hub --- Spoke2
    Hub --- Spoke3
    FW -->|Egress Filter| AKS
    Entra -->|RBAC / Workload Identity| AKS
    Monitor -->|Prometheus| AKS

    classDef internet fill:#ff6b6b,stroke:#c0392b,color:#fff,stroke-width:2px
    classDef hub fill:#3498db,stroke:#2980b9,color:#fff,stroke-width:2px
    classDef aks fill:#2ecc71,stroke:#27ae60,color:#fff,stroke-width:2px
    classDef data fill:#9b59b6,stroke:#8e44ad,color:#fff,stroke-width:2px
    classDef mgmt fill:#f39c12,stroke:#d35400,color:#fff,stroke-width:2px
    classDef shared fill:#1abc9c,stroke:#16a085,color:#fff,stroke-width:2px

    class Users internet
    class FW,Bastion,AppGW,Monitor,DNS hub
    class AKS,ACR,KV1 aks
    class PG,Storage data
    class KV2,DNS2,ACR2 mgmt
    class Entra,Policy,Defender shared
```

---

## KAITO Deployment Flow

```mermaid
sequenceDiagram
    box rgb(255, 107, 107) User
        participant User as User/kubectl
    end
    box rgb(52, 152, 219) Kubernetes Control Plane
        participant API as K8s API Server
        participant WC as Workspace Controller
    end
    box rgb(243, 156, 18) GPU Management
        participant GP as GPU Provisioner
        participant ARM as Azure Resource Manager
    end
    box rgb(46, 204, 113) Inference Layer
        participant Node as GPU Node
        participant vLLM as vLLM Inference
    end

    User->>API: kubectl apply -f workspace.yaml
    API->>WC: Workspace CR created
    WC->>WC: Validate GPU SKU + preset
    WC->>API: Create Machine CR
    GP->>API: Watch Machine CRs
    GP->>ARM: Provision GPU VM (e.g., NC80adIS_H100)
    ARM-->>GP: VM Ready
    GP->>API: Node joins cluster with labels
    WC->>API: Create Deployment + Service
    Note over Node: initContainer downloads model
    Node->>vLLM: Load model into GPU VRAM
    vLLM-->>API: Pod Ready (health check passes)
    WC->>API: Update status: WorkspaceSucceeded
    User->>vLLM: POST /v1/chat/completions
```


---

## AKS Cluster - Kubernetes Resources

```mermaid
graph TB
    subgraph AKS["AKS Cluster (KAITO Enabled)"]
        subgraph NS_System["Namespace: kube-system"]
            CoreDNS[CoreDNS]
            Metrics[Metrics Server]
            NVIDIA[NVIDIA Device Plugin]
        end

        subgraph NS_KAITO["Namespace: kaito-workspace"]
            WC[Workspace Controller]
        end

        subgraph NS_GPU["Namespace: gpu-provisioner"]
            GProv[GPU Provisioner<br/>Karpenter-based]
        end

        subgraph NS_RAG["Namespace: kaito-ragengine"]
            RAGCtrl[RAGEngine Controller]
        end

        subgraph NS_Ingress["Namespace: ingress-nginx"]
            Ingress[NGINX Ingress Controller<br/>LoadBalancer: 10.1.0.100]
        end

        subgraph NS_App["Namespace: app"]
            Streamlit[Streamlit Frontend<br/>Replicas: 2]
            StreamlitSvc[Service: streamlit-frontend]
            StreamlitIngress[Ingress: ai.contoso.com]
        end

        subgraph NS_Default["Namespace: default (Workloads)"]
            WS_CR[Workspace CR:<br/>workspace-llama3]
            WS_Deploy[Deployment:<br/>workspace-llama3]
            WS_Svc[Service:<br/>workspace-llama3:80]
            RAG_CR[RAGEngine CR:<br/>rag-llama3]
            RAG_Deploy[Deployment:<br/>rag-llama3]
            RAG_Svc[Service:<br/>rag-llama3:80]
        end

        subgraph Nodes["Node Pools"]
            SysNode[System Pool<br/>3x D4s_v5<br/>No GPU]
            GPUNode[GPU Pool<br/>1x NC80adIS_H100_v5<br/>8x H100 640GB VRAM]
        end
    end

    WC -->|Reconciles| WS_CR
    WC -->|Creates| WS_Deploy
    WC -->|Creates| WS_Svc
    GProv -->|Provisions| GPUNode
    RAGCtrl -->|Reconciles| RAG_CR
    RAGCtrl -->|Creates| RAG_Deploy
    Streamlit -->|HTTP| WS_Svc
    Streamlit -->|HTTP| RAG_Svc
    Ingress -->|Routes| StreamlitSvc
    WS_Deploy -->|Runs on| GPUNode
    RAG_Deploy -->|Runs on| GPUNode

    classDef system fill:#636e72,stroke:#2d3436,color:#fff,stroke-width:2px
    classDef kaito fill:#6c5ce7,stroke:#5b4cdb,color:#fff,stroke-width:2px
    classDef gpu fill:#fdcb6e,stroke:#f39c12,color:#2d3436,stroke-width:2px
    classDef rag fill:#e17055,stroke:#d63031,color:#fff,stroke-width:2px
    classDef ingress fill:#00b894,stroke:#00a381,color:#fff,stroke-width:2px
    classDef app fill:#74b9ff,stroke:#0984e3,color:#2d3436,stroke-width:2px
    classDef workload fill:#a29bfe,stroke:#6c5ce7,color:#fff,stroke-width:2px
    classDef nodes fill:#55efc4,stroke:#00b894,color:#2d3436,stroke-width:2px
    classDef gpunode fill:#ff7675,stroke:#d63031,color:#fff,stroke-width:2px

    class CoreDNS,Metrics,NVIDIA system
    class WC kaito
    class GProv gpu
    class RAGCtrl rag
    class Ingress ingress
    class Streamlit,StreamlitSvc,StreamlitIngress app
    class WS_CR,WS_Deploy,WS_Svc,RAG_CR,RAG_Deploy,RAG_Svc workload
    class SysNode nodes
    class GPUNode gpunode
```

---

## KAITO Workspace Pod Architecture

```mermaid
graph LR
    subgraph GPU_Node["GPU Node: Standard_NC80adIS_H100_v5"]
        subgraph Pod["Pod: workspace-llama3"]
            Init[initContainer:<br/>model-weights-downloader<br/>Downloads from HuggingFace]
            vLLM[Container: vllm-inference<br/>Port: 5000<br/>GPU Memory: 85%]
            Vol[(Volume:<br/>/workspace/vllm/weights)]
        end
        
        subgraph GPUs["8x NVIDIA H100 80GB NVL"]
            GPU1[H100 no.1]
            GPU2[H100 no.2]
            GPU3[H100 no.3]
            GPU4[H100 no.4]
            GPU5[H100 no.5]
            GPU6[H100 no.6]
            GPU7[H100 no.7]
            GPU8[H100 no.8]
        end
    end

    subgraph Service["Service: workspace-llama3"]
        EP[ClusterIP:80 to Pod:5000]
    end

    Init -->|Downloads weights| Vol
    Vol -->|Mounted| vLLM
    vLLM -->|Tensor Parallel| GPUs
    EP -->|Traffic| vLLM

    subgraph Endpoints["OpenAI-Compatible API"]
        Chat[POST /v1/chat/completions]
        Comp[POST /v1/completions]
        Models[GET /v1/models]
        Health[GET /health]
        Prom[GET /metrics]
    end

    Service --> Endpoints

    classDef initC fill:#fdcb6e,stroke:#f39c12,color:#2d3436,stroke-width:2px
    classDef vllmC fill:#6c5ce7,stroke:#5b4cdb,color:#fff,stroke-width:2px
    classDef volume fill:#00cec9,stroke:#00b894,color:#2d3436,stroke-width:2px
    classDef gpuChip fill:#ff7675,stroke:#d63031,color:#fff,stroke-width:2px
    classDef svc fill:#74b9ff,stroke:#0984e3,color:#2d3436,stroke-width:2px
    classDef endpoint fill:#55efc4,stroke:#00b894,color:#2d3436,stroke-width:2px

    class Init initC
    class vLLM vllmC
    class Vol volume
    class GPU1,GPU2,GPU3,GPU4,GPU5,GPU6,GPU7,GPU8 gpuChip
    class EP svc
    class Chat,Comp,Models,Health,Prom endpoint
```


---

## Data Flow: RAG Pipeline

```mermaid
flowchart LR
    subgraph Client
        UI[Streamlit Chat UI]
    end

    subgraph AKS["AKS Cluster"]
        subgraph RAG["RAG Pipeline"]
            Embed[Embedding Model<br/>bge-small / llama3]
            Vector[(pgvector<br/>Vector Store)]
            Retriever[Context Retriever]
        end

        subgraph Inference["KAITO Workspace"]
            LLM[Llama 3 70B<br/>vLLM on 8x H100]
        end
    end

    subgraph Data["Azure Data Services"]
        PG[(PostgreSQL Flex<br/>+ pgvector)]
        Blob[Azure Blob Storage<br/>Documents]
    end

    UI -->|1. User Query| Retriever
    Retriever -->|2. Embed Query| Embed
    Embed -->|3. Vector Search| PG
    PG -->|4. Relevant Chunks| Retriever
    Retriever -->|5. Query + Context| LLM
    LLM -->|6. Generated Answer| UI
    Blob -->|Document Ingestion| Embed
    Embed -->|Store Embeddings| PG

    classDef client fill:#ff6b6b,stroke:#ee5a24,color:#fff,stroke-width:2px
    classDef embed fill:#fdcb6e,stroke:#f39c12,color:#2d3436,stroke-width:2px
    classDef retriever fill:#74b9ff,stroke:#0984e3,color:#2d3436,stroke-width:2px
    classDef llm fill:#6c5ce7,stroke:#5b4cdb,color:#fff,stroke-width:2px
    classDef db fill:#00cec9,stroke:#00b894,color:#2d3436,stroke-width:2px
    classDef storage fill:#fab1a0,stroke:#e17055,color:#2d3436,stroke-width:2px

    class UI client
    class Embed embed
    class Retriever retriever
    class LLM llm
    class PG,Vector db
    class Blob storage
```

---

## Network Security Architecture

```mermaid
flowchart TB
    subgraph External
        Internet((Internet))
    end

    subgraph Hub["Hub VNet"]
        AppGW[App Gateway<br/>WAF v2 + OWASP 3.2]
        FW[Azure Firewall<br/>Egress Filtering]
        Bastion[Azure Bastion<br/>Admin Access]
    end

    subgraph AKS_VNet["AKS VNet (Spoke 1)"]
        AKS_LB[Internal LB<br/>10.1.0.100]
        AKS_Pods[AKS Pods]
    end

    subgraph Data_VNet["Data VNet (Spoke 2)"]
        PG_PE[PostgreSQL<br/>Private Endpoint]
    end

    Internet -->|HTTPS 443| AppGW
    AppGW -->|Backend| AKS_LB
    AKS_LB --> AKS_Pods
    AKS_Pods -->|All Egress| FW
    FW -->|Allowed FQDNs only| Internet
    AKS_Pods -->|Port 5432| PG_PE
    Bastion -->|SSH/RDP| AKS_Pods

    subgraph FW_Rules["Firewall Allowed FQDNs"]
        R1[*.huggingface.co]
        R2[mcr.microsoft.com]
        R3[*.docker.io]
        R4[pypi.org]
        R5[*.blob.core.windows.net]
    end

    FW -.-> FW_Rules

    classDef internet fill:#e74c3c,stroke:#c0392b,color:#fff,stroke-width:2px
    classDef firewall fill:#e67e22,stroke:#d35400,color:#fff,stroke-width:2px
    classDef gateway fill:#3498db,stroke:#2980b9,color:#fff,stroke-width:2px
    classDef bastion fill:#9b59b6,stroke:#8e44ad,color:#fff,stroke-width:2px
    classDef aks fill:#2ecc71,stroke:#27ae60,color:#fff,stroke-width:2px
    classDef data fill:#1abc9c,stroke:#16a085,color:#fff,stroke-width:2px
    classDef rules fill:#f1c40f,stroke:#f39c12,color:#2d3436,stroke-width:1px

    class Internet internet
    class FW firewall
    class AppGW gateway
    class Bastion bastion
    class AKS_LB,AKS_Pods aks
    class PG_PE data
    class R1,R2,R3,R4,R5 rules
```

---

## Workspace Status Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Pending: kubectl apply workspace.yaml
    Pending --> ResourceReady: GPU Node Provisioned
    ResourceReady --> InferenceReady: Model Loaded + vLLM Running
    InferenceReady --> WorkspaceSucceeded: All Health Checks Pass
    WorkspaceSucceeded --> [*]: Ready to serve traffic
    
    Pending --> Failed: Invalid SKU / No Quota
    ResourceReady --> Failed: Model Download Error
    InferenceReady --> Failed: OOM / GPU Error
    Failed --> Pending: Fix and Reapply

    classDef pending fill:#fdcb6e,stroke:#f39c12,color:#2d3436
    classDef ready fill:#74b9ff,stroke:#0984e3,color:#2d3436
    classDef inference fill:#a29bfe,stroke:#6c5ce7,color:#fff
    classDef success fill:#55efc4,stroke:#00b894,color:#2d3436
    classDef fail fill:#ff7675,stroke:#d63031,color:#fff

    class Pending pending
    class ResourceReady ready
    class InferenceReady inference
    class WorkspaceSucceeded success
    class Failed fail
```

---

## Monitoring and Observability Stack

```mermaid
graph TB
    subgraph AKS["AKS Cluster"]
        vLLM[vLLM Pod<br/>/metrics endpoint]
        SM[ServiceMonitor<br/>azmonitoring.coreos.com/v1]
    end

    subgraph Azure_Monitor["Azure Monitor"]
        Prometheus[Azure Managed Prometheus<br/>Scrapes every 30s]
        Grafana[Azure Managed Grafana<br/>vLLM Dashboard]
        LA[Log Analytics Workspace]
    end

    subgraph Metrics["Key vLLM Metrics"]
        M1[vllm:num_requests_running]
        M2[vllm:num_requests_waiting]
        M3[vllm:gpu_cache_usage_perc]
        M4[vllm:avg_generation_throughput]
        M5[vllm:time_to_first_token_seconds]
    end

    vLLM -->|Expose| SM
    SM -->|Scrape| Prometheus
    Prometheus -->|Visualize| Grafana
    AKS -->|Container Logs| LA
    Grafana --> Metrics

    classDef vllmC fill:#6c5ce7,stroke:#5b4cdb,color:#fff,stroke-width:2px
    classDef monitor fill:#00b894,stroke:#00a381,color:#fff,stroke-width:2px
    classDef prom fill:#fdcb6e,stroke:#f39c12,color:#2d3436,stroke-width:2px
    classDef grafana fill:#e17055,stroke:#d63031,color:#fff,stroke-width:2px
    classDef logs fill:#74b9ff,stroke:#0984e3,color:#2d3436,stroke-width:2px
    classDef metric fill:#dfe6e9,stroke:#b2bec3,color:#2d3436,stroke-width:1px

    class vLLM vllmC
    class SM monitor
    class Prometheus prom
    class Grafana grafana
    class LA logs
    class M1,M2,M3,M4,M5 metric
```

---

## KAITO vs Traditional Deployment

```mermaid
gantt
    title Deployment Time Comparison
    dateFormat X
    axisFormat %s min

    section Traditional
    Create GPU Node Pool     :a1, 0, 5
    Install NVIDIA Drivers   :a2, after a1, 2
    Download Model           :a3, after a2, 30
    Deploy vLLM Server       :a4, after a3, 5
    Configure Service        :a5, after a4, 2
    Health Checks Setup      :a6, after a5, 1

    section KAITO
    Apply Workspace YAML     :b1, 0, 1
    Auto GPU Provisioning    :b2, after b1, 5
    Auto Model Download      :b3, after b2, 7
    Auto Service Ready       :b4, after b3, 2
```


---

## Supported GPU SKUs

| SKU | GPU | Count | VRAM | Best For |
|-----|-----|-------|------|----------|
| Standard_NC4as_T4_v3 | T4 | 1 | 16 GB | Small models, dev/test |
| Standard_NV36ads_A10_v5 | A10 | 1 | 24 GB | **Recommended** - Phi-4, small Llama |
| Standard_NC24ads_A100_v4 | A100 | 1 | 80 GB | Medium models (13B-30B) |
| Standard_NC96ads_A100_v4 | A100 | 4 | 320 GB | Large models (70B) |
| Standard_NC80adis_H100_v5 | H100 | 2 | 188 GB | Large models, high throughput |
| Standard_ND96isr_H100_v5 | H100 | 8 | 640 GB | 70B+ models, multi-node |
| Standard_ND96isr_H200_v5 | H200 | 8 | 1128 GB | Largest models |

---

## Quick Start

```yaml
# workspace-phi4.yaml - Deploy Phi-4 in 15 lines!
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

# Check status
kubectl get workspace
```

---

## Headlamp Integration

```mermaid
graph LR
    subgraph Developer["Developer Workstation"]
        HL[Headlamp Desktop App]
        KC[~/.kube/config]
    end

    subgraph Plugins["Headlamp Plugins"]
        KP[KAITO Plugin<br/>Model Catalog]
        Chat[Chat Interface<br/>Test Prompts]
        Dash[Cluster Dashboard<br/>Nodes, Pods, Events]
    end

    subgraph AKS["AKS Cluster"]
        API[K8s API Server]
        WS[Workspace CRs]
        Pods[Running Pods]
    end

    HL -->|Reads| KC
    HL --> Plugins
    KP -->|CRUD Workspaces| API
    Chat -->|Inference Requests| WS
    Dash -->|Monitor| Pods
    API --> WS
    API --> Pods

    classDef dev fill:#74b9ff,stroke:#0984e3,color:#2d3436,stroke-width:2px
    classDef plugin fill:#a29bfe,stroke:#6c5ce7,color:#fff,stroke-width:2px
    classDef cluster fill:#55efc4,stroke:#00b894,color:#2d3436,stroke-width:2px
    classDef chat fill:#fd79a8,stroke:#e84393,color:#fff,stroke-width:2px

    class HL,KC dev
    class KP,Dash plugin
    class Chat chat
    class API,WS,Pods cluster
```

---

<footer>
Built for the Azure and Kubernetes community
</footer>
