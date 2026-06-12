---
layout: default
title: "Quick Reference"
nav_order: 14
---

# Quick Reference
{: .no_toc }

<details open markdown="block">
  <summary>Table of contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## Scripts

| Script | Purpose | Command |
|--------|---------|---------|
| `demokaitoheadlamp.sh` | Full demo (all steps) | `bash demokaitoheadlamp.sh` |
| `demo-env.sh` | Environment variables | `source demo-env.sh` |
| `workspace-phi4.yaml` | Phi-4 workspace manifest | `kubectl apply -f workspace-phi4.yaml` |
| `workspace-llama31.yaml` | Llama 3.1 workspace manifest | `kubectl apply -f workspace-llama31.yaml` |
| `streamlit_app.py` | Chat UI | `streamlit run streamlit_app.py` |
| `servicemonitor.yaml` | Prometheus scrape config | `kubectl apply -f servicemonitor.yaml` |

---

## Key Commands

```bash
# Create cluster with KAITO
az aks create --resource-group $RG_NAME --name $AKS_NAME \
  --enable-ai-toolchain-operator --network-plugin azure \
  --network-plugin-mode overlay --enable-oidc-issuer

# Deploy model
kubectl apply -f workspace-phi4.yaml

# Watch status
kubectl get workspace -w

# Test inference
kubectl port-forward svc/workspace-phi-4-mini-instruct 8080:80 &
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"phi-4-mini-instruct","messages":[{"role":"user","content":"Hello!"}]}'

# Check metrics
curl http://localhost:8080/metrics | grep vllm

# Cleanup
kubectl delete workspace workspace-phi-4-mini-instruct
az group delete --name $RG_NAME --yes
```

---

## GPU SKUs Supported by KAITO

| SKU | GPU | VRAM | Use Case |
|-----|-----|------|----------|
| Standard_NV36ads_A10_v5 | 1x A10 | 24GB | Small models (Phi-4, Llama-8B) |
| Standard_NV72ads_A10_v5 | 2x A10 | 48GB | Medium models |
| Standard_NC24ads_A100_v4 | 1x A100 | 80GB | Large models |
| Standard_NC48ads_A100_v4 | 2x A100 | 160GB | 70B models |
| Standard_NC96ads_A100_v4 | 4x A100 | 320GB | Multi-GPU inference |

---

## Workspace CR Reference

```yaml
apiVersion: kaito.sh/v1beta1
kind: Workspace
metadata:
  name: <workspace-name>
  namespace: default
resource:
  instanceType: "<GPU-SKU>"
  labelSelector:
    matchLabels:
      apps: <model-label>
inference:
  preset:
    name: <model-name>           # e.g., phi-4-mini-instruct
    accessMode: public|private   # private requires modelAccessSecret
    presetOptions:
      modelAccessSecret: <secret-name>  # for private models
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Workspace stuck in Pending | No GPU quota | Request quota increase |
| Node provisioning timeout | Region capacity | Try different region |
| Pod OOMKilled | Model too large for GPU | Use larger SKU or reduce max_model_len |
| InferenceReady=False | Model download failed | Check pod logs: `kubectl logs <pod>` |
| Connection refused on :8080 | Port-forward not active | Restart port-forward |

---

## References

- [KAITO Official Docs](https://kaito-project.github.io/kaito/docs/)
- [KAITO on AKS (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/aks/ai-toolchain-operator)
- [vLLM Documentation](https://docs.vllm.ai/)
- [Headlamp](https://headlamp.dev/)
- [KAITO GitHub](https://github.com/kaito-project/kaito)
