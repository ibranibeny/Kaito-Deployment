---
layout: default
title: "2. Architecture"
nav_order: 4
---

# Architecture
{: .no_toc }

System design and component interactions for KAITO on AKS.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## 2.1 High-Level Architecture

```mermaid
flowchart TB
    subgraph Azure["Azure Cloud"]
        subgraph AKS["AKS Cluster"]
            subgraph System["System Node Pool (D4s_v3)"]
                KAITO["KAITO Controller"]
                GPU_PROV["gpu-provisioner"]
                HEADLAMP["Headlamp"]
            end
            subgraph GPUPool["GPU Node Pool (NV36ads_A10_v5)"]
                VLLM["vLLM Pod\n(Model Inference)"]
            end
        end
        MONITOR["Azure Monitor\nPrometheus + Grafana"]
    end
    
    USER["👤 User"] -->|kubectl apply| AKS
    KAITO -->|"Create Machine CR"| GPU_PROV
    GPU_PROV -->|"Provision GPU Node"| GPUPool
    KAITO -->|"Create Deployment"| VLLM
    VLLM -->|"metrics"| MONITOR
    USER -->|"POST /v1/chat/completions"| VLLM
    
    classDef azure fill:#0078d4,stroke:#005a9e,color:#fff
    classDef gpu fill:#76b900,stroke:#5a8c00,color:#fff
    classDef user fill:#f25022,stroke:#c43e1c,color:#fff
    classDef monitor fill:#7fba00,stroke:#5f8c00,color:#fff
    
    class Azure azure
    class GPUPool,VLLM gpu
    class USER user
    class MONITOR monitor
```

---

## 2.2 Kubernetes Resource Map

```mermaid
flowchart TB
    subgraph NS_SYSTEM["namespace: kube-system"]
        KAITO_CTL["Deployment: kaito-workspace"]
        GPU_CTL["Deployment: kaito-gpu-provisioner"]
        NVIDIA["DaemonSet: nvidia-device-plugin"]
    end
    
    subgraph NS_DEFAULT["namespace: default"]
        WS["Workspace CR\nworkspace-phi-4-mini-instruct"]
        DEP["Deployment: workspace-phi-4-mini-instruct"]
        SVC["Service: workspace-phi-4-mini-instruct\nClusterIP :80 → :8080"]
        CM["ConfigMap: phi4-inference-config"]
        POD["Pod: vLLM container\n(nvidia.com/gpu: 1)"]
    end
    
    KAITO_CTL -->|watches| WS
    WS -->|triggers| GPU_CTL
    KAITO_CTL -->|creates| DEP
    KAITO_CTL -->|creates| SVC
    DEP -->|manages| POD
    CM -->|mounts config| POD
    NVIDIA -->|exposes GPU| POD
    
    classDef system fill:#1565c0,stroke:#0d47a1,color:#fff
    classDef workload fill:#2e7d32,stroke:#1b5e20,color:#fff
    classDef crd fill:#f57c00,stroke:#e65100,color:#fff
    
    class NS_SYSTEM,KAITO_CTL,GPU_CTL,NVIDIA system
    class DEP,SVC,CM,POD workload
    class WS crd
```

---

## 2.3 Network Topology (Production)

```mermaid
flowchart TB
    subgraph Hub["Hub VNet (10.0.0.0/16)"]
        FW["Azure Firewall\nEgress filtering"]
        BASTION["Azure Bastion\nAdmin access"]
        MONITOR2["Azure Monitor\nPrometheus + Grafana"]
    end
    
    subgraph Spoke1["Spoke: AKS VNet (10.1.0.0/16)"]
        AKS2["AKS Cluster\nKAITO + GPU Nodes"]
        ACR["ACR (Private)\nContainer images"]
        KV["Key Vault\nSecrets (HF Token)"]
    end
    
    subgraph Spoke2["Spoke: Data VNet (10.2.0.0/16)"]
        PG["PostgreSQL Flex\npgvector"]
        STORAGE["Azure Storage\nDocuments"]
    end
    
    Hub ---|VNet Peering| Spoke1
    Hub ---|VNet Peering| Spoke2
    AKS2 -->|"UDR"| FW
    FW -->|"*.huggingface.co"| INTERNET["Internet"]
    AKS2 -->|Private Endpoint| PG
    AKS2 -->|Private Endpoint| ACR
    
    classDef hub fill:#6a1b9a,stroke:#4a148c,color:#fff
    classDef spoke fill:#0078d4,stroke:#005a9e,color:#fff
    classDef data fill:#00695c,stroke:#004d40,color:#fff
    classDef ext fill:#455a64,stroke:#263238,color:#fff
    
    class Hub,FW,BASTION,MONITOR2 hub
    class Spoke1,AKS2,ACR,KV spoke
    class Spoke2,PG,STORAGE data
    class INTERNET ext
```

---

## 2.4 KAITO Workspace Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Pending: kubectl apply
    Pending --> Provisioning: KAITO creates Machine CR
    Provisioning --> NodeReady: GPU node joins cluster
    NodeReady --> ModelLoading: vLLM pod starts
    ModelLoading --> InferenceReady: Model loaded ✅
    InferenceReady --> Scaling: HPA triggered
    Scaling --> InferenceReady: Scale complete
    InferenceReady --> Deleting: kubectl delete
    Deleting --> [*]: GPU node deprovisioned
    
    Provisioning --> Failed: Quota exceeded
    ModelLoading --> Failed: OOM / Download error
    Failed --> Pending: Fix & reapply
```

---

## 2.5 Deployment Flow

```mermaid
sequenceDiagram
    participant User
    participant CLI as az CLI
    participant AKS as AKS Cluster
    participant KAITO as KAITO Controller
    participant GPU as gpu-provisioner
    participant vLLM as vLLM Pod

    User->>CLI: az aks create --enable-ai-toolchain-operator
    CLI->>AKS: Create cluster + install KAITO
    User->>AKS: kubectl apply -f workspace-phi4.yaml
    AKS->>KAITO: Workspace CR detected
    KAITO->>GPU: Request GPU node
    GPU->>AKS: Add NV36ads_A10_v5 node
    Note over AKS: ~5-10 min for GPU node
    KAITO->>vLLM: Create Deployment (vLLM + model)
    vLLM->>vLLM: Download & load model
    Note over vLLM: ~5 min for model load
    vLLM-->>User: Ready! POST /v1/chat/completions
```

---

[← Overview]({{ site.baseurl }}{% link modules/01-overview.md %}){: .btn .mr-2 }
[Next: Prerequisites →]({{ site.baseurl }}{% link modules/03-prerequisites.md %}){: .btn .btn-primary }
