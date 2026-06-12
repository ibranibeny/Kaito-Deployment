---
layout: default
title: "8. Monitoring"
nav_order: 10
---

# Monitoring & Observability
{: .no_toc }

Monitor vLLM inference performance with Prometheus and Grafana.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## 8.1 vLLM Metrics

The vLLM inference server exposes Prometheus metrics on port 8080 at `/metrics`:

| Metric | Description |
|--------|-------------|
| `vllm:request_success_total` | Total successful requests |
| `vllm:request_duration_seconds` | Request latency histogram |
| `vllm:num_requests_running` | Currently processing requests |
| `vllm:num_requests_waiting` | Requests in queue |
| `vllm:gpu_cache_usage_perc` | GPU KV cache utilization |
| `vllm:cpu_cache_usage_perc` | CPU KV cache utilization |
| `vllm:avg_generation_throughput_toks_per_s` | Tokens generated per second |

---

## 8.2 Enable Azure Monitor (Prometheus)

```bash
# Enable monitoring add-on
az aks update \
    --resource-group $RG_NAME \
    --name $AKS_NAME \
    --enable-azure-monitor-metrics
```

---

## 8.3 ServiceMonitor for vLLM

Create a ServiceMonitor to scrape vLLM metrics:

```yaml
# servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kaito-vllm-monitor
  namespace: default
spec:
  selector:
    matchLabels:
      apps: phi-4-mini-instruct
  endpoints:
  - port: http
    path: /metrics
    interval: 30s
```

```bash
kubectl apply -f servicemonitor.yaml
```

---

## 8.4 Grafana Dashboard

Import the vLLM dashboard in Azure Managed Grafana:

1. Navigate to your Grafana instance in Azure Portal
2. Click **Dashboards → Import**
3. Use dashboard ID or paste the JSON from the vLLM community dashboards
4. Select your Prometheus data source

### Key Panels

| Panel | Shows |
|-------|-------|
| Request Rate | Requests/second over time |
| Latency (P50/P95/P99) | Response time percentiles |
| GPU Cache Utilization | KV cache pressure |
| Tokens/Second | Generation throughput |
| Queue Depth | Waiting requests |

---

## 8.5 Quick Metrics Check

```bash
# Port-forward and check raw metrics
kubectl port-forward svc/workspace-phi-4-mini-instruct 8080:80 &
curl -s http://localhost:8080/metrics | grep vllm | head -20
```

---

[← Test Inference]({{ site.baseurl }}{% link modules/07-test-inference.md %}){: .btn .mr-2 }
[Next: Cleanup →]({{ site.baseurl }}{% link modules/09-cleanup.md %}){: .btn .btn-primary }
