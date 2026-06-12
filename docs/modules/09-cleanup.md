---
layout: default
title: "9. Cleanup"
nav_order: 11
---

# Cleanup
{: .no_toc }

Destroy all Azure resources created during the workshop.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## 9.1 Delete Workspace First

Delete the workspace to deprovision GPU nodes:

```bash
kubectl delete workspace workspace-phi-4-mini-instruct
```

{: .note }
> Wait ~2 minutes for the GPU node to be deprovisioned before deleting the cluster.

---

## 9.2 Delete Resource Group

This removes the AKS cluster, managed identity, and all associated resources:

```bash
source ./demo-env.sh
az group delete --name $RG_NAME --yes --no-wait
```

---

## 9.3 Verify Cleanup

```bash
az group show --name $RG_NAME 2>/dev/null && echo "Still exists" || echo "Deleted ✅"
```

---

## 9.4 Clean Local Files

```bash
# Remove kubeconfig
rm -f ~/.kube/config-kaito-*

# Remove env file
rm -f ./demo-env.sh
```

---

## What's Next?

- Explore [KAITO GitHub](https://github.com/kaito-project/kaito) for more models
- Try [multi-node deployment](https://github.com/ibranibeny/Kaito-Deployment/blob/main/README-multinode.md) for larger models
- Set up [RAG pipeline](https://learn.microsoft.com/en-us/azure/aks/ai-toolchain-operator) with pgvector
- Configure [Azure API Management](https://learn.microsoft.com/en-us/azure/api-management/) as an AI gateway

---

[← Monitoring]({{ site.baseurl }}{% link modules/08-monitoring.md %}){: .btn .mr-2 }
[Back to Home]({{ site.baseurl }}/){: .btn }
