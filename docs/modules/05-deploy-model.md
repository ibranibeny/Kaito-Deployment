---
layout: default
title: "5. Deploy Model"
nav_order: 7
---

# Deploy AI Model with KAITO
{: .no_toc }

Apply a Workspace manifest to deploy an AI model.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## 5.1 Choose a Model

| Model | File | GPU | Access |
|-------|------|-----|--------|
| Phi-4-mini-instruct (recommended) | `workspace-phi4.yaml` | 1x A10 | Public |
| Llama-3.1-8B-instruct | `workspace-llama31.yaml` | 1x A10 | Private (HF token) |

For this workshop, we recommend **Phi-4-mini-instruct** — no authentication required.

---

## 5.2 Create Inference Config (Optional)

Optimize vLLM settings for the A10 GPU:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: phi4-inference-config
  namespace: default
data:
  inference_config.yaml: |
    max_probe_steps: 6
    kv_cache_cpu_memory_utilization: 0.5
    vllm:
      gpu-memory-utilization: 0.85
      max-model-len: 65536
      cpu-offload-gb: 0
      swap-space: 4
EOF
```

---

## 5.3 Deploy Phi-4 Workspace

```yaml
# workspace-phi4.yaml
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
kubectl apply -f workspace-phi4.yaml
```

---

## 5.4 Deploy Llama 3.1 (Alternative)

{: .warning }
> Llama requires a HuggingFace token. Create a secret first:
> ```bash
> kubectl create secret generic hf-token --from-literal=HF_TOKEN=<your-token>
> ```

```yaml
# workspace-llama31.yaml
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

---

## 5.5 Monitor Deployment

```bash
# Watch workspace status
kubectl get workspace -w

# Check events
kubectl describe workspace workspace-phi-4-mini-instruct

# Watch pods
kubectl get pods -w
```

### Expected Timeline

| Phase | Duration | What Happens |
|-------|----------|-------------|
| Pending → Provisioning | ~1 min | KAITO creates Machine CR |
| Provisioning → NodeReady | ~5-10 min | GPU VM provisioned & joins cluster |
| NodeReady → InferenceReady | ~5 min | vLLM downloads model & starts serving |

---

## 5.6 Verify Deployment

```bash
# Should show WORKSPACEREADY=True, INFERENCEREADY=True
kubectl get workspace

# Check the inference pod
kubectl get pods -l apps=phi-4-mini-instruct

# Check the service
kubectl get svc workspace-phi-4-mini-instruct
```

---

[← Deploy Cluster]({{ site.baseurl }}{% link modules/04-deploy-cluster.md %}){: .btn .mr-2 }
[Next: Headlamp →]({{ site.baseurl }}{% link modules/06-headlamp.md %}){: .btn .btn-primary }
