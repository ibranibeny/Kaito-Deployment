---
layout: home
title: Home
nav_order: 1
description: "Deploy AI models on AKS with KAITO — automated GPU provisioning, model deployment, and inference in one YAML"
permalink: /
---

# KAITO on AKS
{: .fs-9 }

Deploy AI models on Azure Kubernetes Service with **one YAML manifest**. KAITO automates GPU provisioning, model downloading, and inference server setup.
{: .fs-6 .fw-300 }

[Get Started]({{ site.baseurl }}{% link modules/01-overview.md %}){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View Architecture]({{ site.baseurl }}{% link architecture.md %}){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## What You'll Learn

- How KAITO simplifies AI model deployment on Kubernetes
- Deploying GPU-accelerated inference with a single manifest
- Managing KAITO workspaces with Headlamp GUI
- Monitoring inference performance with Prometheus & Grafana

---

## Architecture at a Glance

| Component | Technology | Purpose |
|---|---|---|
| 🤖 KAITO | AI Toolchain Operator | Automates model deployment & GPU provisioning |
| ☸️ AKS | Azure Kubernetes Service | Managed Kubernetes cluster |
| 🖥️ GPU | Standard_NV36ads_A10_v5 | NVIDIA A10 (24GB VRAM) for inference |
| ⚡ vLLM | Inference Engine | High-performance serving with continuous batching |
| 🎛️ Headlamp | Kubernetes GUI | Visual management with KAITO plugin |
| 📊 Monitoring | Prometheus + Grafana | vLLM metrics & GPU utilization |

---

## Workshop Modules

| # | Module | Duration | Description |
|---|---|---|---|
| 1 | [Overview]({{ site.baseurl }}{% link modules/01-overview.md %}) | 10 min | What is KAITO and why use it |
| 2 | [Architecture]({{ site.baseurl }}{% link modules/02-architecture.md %}) | 10 min | System design & components |
| 3 | [Prerequisites]({{ site.baseurl }}{% link modules/03-prerequisites.md %}) | 5 min | Tools & Azure setup |
| 4 | [Deploy Cluster]({{ site.baseurl }}{% link modules/04-deploy-cluster.md %}) | 15 min | Create AKS with KAITO enabled |
| 5 | [Deploy Model]({{ site.baseurl }}{% link modules/05-deploy-model.md %}) | 15 min | Apply workspace manifest |
| 6 | [Headlamp]({{ site.baseurl }}{% link modules/06-headlamp.md %}) | 10 min | Install GUI + KAITO plugin |
| 7 | [Test Inference]({{ site.baseurl }}{% link modules/07-test-inference.md %}) | 10 min | Query the model |
| 8 | [Monitoring]({{ site.baseurl }}{% link modules/08-monitoring.md %}) | 10 min | Prometheus & Grafana |
| 9 | [Cleanup]({{ site.baseurl }}{% link modules/09-cleanup.md %}) | 5 min | Destroy resources |

**Total estimated time: ~1.5 hours**
{: .fs-5 .fw-300 }

---

## KAITO vs Traditional Deployment

| Aspect | Without KAITO | With KAITO |
|--------|---------------|------------|
| GPU Node Pool | Manual creation | ✅ Auto-provisioned |
| NVIDIA Drivers | Manual install | ✅ Pre-configured |
| Model Download | Init containers + PVC | ✅ Automatic |
| Inference Server | Deploy vLLM manually | ✅ Optimized preset |
| Service/Networking | Manual Service + Ingress | ✅ Auto-created |
| Health Checks | Configure probes | ✅ Built-in |
| **Total YAML** | ~300-500 lines | **~15 lines** |

---

## Key Design Decisions

- **KAITO over manual vLLM** — single CRD replaces 300+ lines of YAML
- **Headlamp over kubectl** — visual workspace management for demos
- **Azure CNI Overlay** — required for KAITO node auto-provisioning
- **Standard_NV36ads_A10_v5** — KAITO-supported GPU SKU with 24GB VRAM
- **Phi-4-mini-instruct** — lightweight model ideal for demos on single A10

{: .note }
> This workshop targets `indonesiacentral` region. Ensure your subscription has GPU quota before starting.

