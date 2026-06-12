---
layout: default
title: "7. Test Inference"
nav_order: 9
---

# Test Model Inference
{: .no_toc }

Query the deployed model using the OpenAI-compatible API.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## 7.1 Check Workspace Status

Ensure the workspace is ready before testing:

```bash
kubectl get workspace
```

Expected output:

```
NAME                             INSTANCE                    RESOURCEREADY   INFERENCEREADY   WORKSPACEREADY   AGE
workspace-phi-4-mini-instruct    Standard_NV36ads_A10_v5    True            True             True             15m
```

---

## 7.2 Port-Forward to Service

```bash
kubectl port-forward svc/workspace-phi-4-mini-instruct 8080:80 &
```

---

## 7.3 Test Chat Completions

The model exposes an **OpenAI-compatible** API:

```bash
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi-4-mini-instruct",
    "messages": [
      {"role": "user", "content": "What is Azure Kubernetes Service in one sentence?"}
    ],
    "max_tokens": 100
  }' | jq .
```

### Expected Response

```json
{
  "id": "cmpl-xxx",
  "object": "chat.completion",
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "Azure Kubernetes Service (AKS) is a managed container orchestration service..."
    },
    "finish_reason": "stop"
  }]
}
```

---

## 7.4 Test with Streaming

```bash
curl -s -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi-4-mini-instruct",
    "messages": [
      {"role": "system", "content": "You are a helpful Azure expert."},
      {"role": "user", "content": "Explain KAITO in 3 bullet points."}
    ],
    "max_tokens": 200,
    "stream": true
  }'
```

---

## 7.5 List Available Models

```bash
curl -s http://localhost:8080/v1/models | jq .
```

---

## 7.6 Using the Streamlit UI (Optional)

A Streamlit chat interface is included in the repo:

```bash
# Install dependencies
pip install streamlit requests

# Run (set the endpoint first)
export KAITO_ENDPOINT="http://localhost:8080"
streamlit run streamlit_app.py
```

---

## 7.7 Cleanup Port-Forward

```bash
# Kill the background port-forward
kill %1
```

---

[← Headlamp]({{ site.baseurl }}{% link modules/06-headlamp.md %}){: .btn .mr-2 }
[Next: Monitoring →]({{ site.baseurl }}{% link modules/08-monitoring.md %}){: .btn .btn-primary }
