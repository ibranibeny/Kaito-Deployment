---
layout: default
title: "Architecture Diagrams"
nav_order: 13
---

# Architecture Diagrams
{: .no_toc }

Visual overview of KAITO on AKS — from high-level topology to pod-level details.
{: .fs-6 .fw-300 }

---

## Network Topology

```mermaid
flowchart TB
    subgraph Azure["Azure Cloud (indonesiacentral)"]
        subgraph Hub["Hub VNet 10.0.0.0/16"]
            FW["Azure Firewall\nEgress: HuggingFace, MCR"]
            BASTION["Azure Bastion"]
            GRAFANA["Grafana + Prometheus"]
        end
        subgraph Spoke["AKS VNet 10.1.0.0/16"]
            subgraph SysPool["System Pool (D4s_v3)"]
                KAITO["KAITO Controller"]
                GPUPROV["gpu-provisioner"]
                HL["Headlamp"]
            end
            subgraph GPUPool["GPU Pool (NV36ads_A10_v5)"]
                VLLM["vLLM\nPhi-4-mini-instruct"]
            end
            ACR["ACR (Private)"]
            KV["Key Vault"]
        end
    end
    
    USER["👤 Developer"] -->|"kubectl / Headlamp"| SysPool
    USER -->|"POST /v1/chat"| VLLM
    KAITO -->|"Machine CR"| GPUPROV
    GPUPROV -->|"Provision"| GPUPool
    GPUPool -->|"Pull images"| ACR
    Spoke -->|"UDR"| FW
    FW -->|"HTTPS"| HF["huggingface.co"]
    VLLM -->|"metrics"| GRAFANA
    
    classDef hub fill:#6a1b9a,stroke:#4a148c,color:#fff
    classDef spoke fill:#1565c0,stroke:#0d47a1,color:#fff
    classDef gpu fill:#76b900,stroke:#5a8c00,color:#fff
    classDef user fill:#f25022,stroke:#c43e1c,color:#fff
    classDef ext fill:#455a64,stroke:#263238,color:#fff
    
    class Hub,FW,BASTION,GRAFANA hub
    class Spoke,SysPool,KAITO,GPUPROV,HL,ACR,KV spoke
    class GPUPool,VLLM gpu
    class USER user
    class HF ext
```

---

## KAITO Deployment Flow

```mermaid
sequenceDiagram
    participant User
    participant API as K8s API Server
    participant KAITO as KAITO Controller
    participant GPU as gpu-provisioner
    participant Azure as Azure VMSS
    participant Pod as vLLM Pod
    participant HF as HuggingFace

    User->>API: kubectl apply workspace-phi4.yaml
    API->>KAITO: Workspace CR created
    KAITO->>KAITO: Validate spec (model exists, SKU supported)
    KAITO->>GPU: Create Machine CR
    GPU->>Azure: Request NV36ads_A10_v5 VM
    Note over Azure: ~5-10 min provisioning
    Azure-->>GPU: VM Ready, node joined
    GPU-->>KAITO: Machine Ready
    KAITO->>API: Create Deployment + Service + ConfigMap
    API->>Pod: Schedule on GPU node
    Pod->>HF: Download model weights
    Note over Pod: ~3-5 min download
    Pod->>Pod: Load model into GPU VRAM
    Pod-->>KAITO: Health check passes
    KAITO-->>User: InferenceReady=True ✅
```

---

## Workspace Pod Architecture

```mermaid
flowchart LR
    subgraph Node["GPU Node: Standard_NV36ads_A10_v5"]
        subgraph Pod["Pod: workspace-phi-4-mini-instruct"]
            VLLM2["Container: vLLM\nImage: vllm/vllm-openai"]
            GPU2["nvidia.com/gpu: 1\n24GB A10 VRAM"]
        end
        NVIDIA2["DaemonSet:\nnvidia-device-plugin"]
    end
    
    SVC["Service\nClusterIP :80"] -->|":8080"| VLLM2
    CM2["ConfigMap\nphi4-inference-config"] -->|mount| VLLM2
    NVIDIA2 -->|"expose GPU"| GPU2
    VLLM2 --- GPU2
    
    classDef node fill:#37474f,stroke:#263238,color:#fff
    classDef pod fill:#1565c0,stroke:#0d47a1,color:#fff
    classDef svc fill:#2e7d32,stroke:#1b5e20,color:#fff
    classDef hw fill:#76b900,stroke:#5a8c00,color:#fff
    
    class Node node
    class Pod,VLLM2 pod
    class SVC,CM2 svc
    class GPU2,NVIDIA2 hw
```

---

## Monitoring Stack

```mermaid
flowchart TB
    subgraph AKS["AKS Cluster"]
        VLLM3["vLLM Pod\n/metrics endpoint"]
        SM["ServiceMonitor\n(scrape every 30s)"]
    end
    
    subgraph Monitor["Azure Monitor"]
        PROM["Managed Prometheus\n(metrics store)"]
        GRAF["Managed Grafana\n(dashboards)"]
    end
    
    SM -->|"scrape"| VLLM3
    PROM -->|"collect"| SM
    GRAF -->|"query"| PROM
    
    GRAF --> D1["📊 Request Rate"]
    GRAF --> D2["📊 Latency P95"]
    GRAF --> D3["📊 GPU Cache %"]
    GRAF --> D4["📊 Tokens/sec"]
    
    classDef aks fill:#0078d4,stroke:#005a9e,color:#fff
    classDef monitor fill:#7fba00,stroke:#5f8c00,color:#fff
    classDef dash fill:#00695c,stroke:#004d40,color:#fff
    
    class AKS,VLLM3,SM aks
    class Monitor,PROM,GRAF monitor
    class D1,D2,D3,D4 dash
```

---

## RAG Pipeline (Advanced)

```mermaid
flowchart LR
    DOC["📄 Documents"] -->|"chunk + embed"| EMBED["Embedding Model\n(text-embedding-3-small)"]
    EMBED -->|"store vectors"| PG["PostgreSQL\npgvector"]
    
    USER2["👤 User Query"] -->|"embed query"| EMBED
    EMBED -->|"similarity search"| PG
    PG -->|"top-k contexts"| PROMPT["Prompt Builder\n(context + question)"]
    PROMPT -->|"POST /v1/chat"| KAITO2["KAITO Workspace\n(Phi-4 / Llama)"]
    KAITO2 -->|"answer"| USER2
    
    classDef data fill:#f57c00,stroke:#e65100,color:#fff
    classDef ai fill:#1565c0,stroke:#0d47a1,color:#fff
    classDef db fill:#00695c,stroke:#004d40,color:#fff
    classDef user fill:#f25022,stroke:#c43e1c,color:#fff
    
    class DOC,PROMPT data
    class EMBED,KAITO2 ai
    class PG db
    class USER2 user
```

---

## KAITO vs Traditional (Timeline)

```mermaid
gantt
    title Deployment Timeline Comparison
    dateFormat X
    axisFormat %M min

    section Without KAITO
    Create GPU Node Pool     :a1, 0, 5
    Install NVIDIA Drivers   :a2, after a1, 2
    Create PVC + Download    :a3, after a2, 15
    Deploy vLLM              :a4, after a3, 5
    Configure Service        :a5, after a4, 2
    Health Check Setup       :a6, after a5, 1

    section With KAITO
    kubectl apply workspace  :b1, 0, 1
    Auto GPU Provisioning    :b2, after b1, 8
    Auto Model + vLLM        :b3, after b2, 5
    Ready ✅                  :milestone, after b3, 0
```

