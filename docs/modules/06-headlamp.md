---
layout: default
title: "6. Headlamp"
nav_order: 8
---

# Headlamp with KAITO Plugin
{: .no_toc }

Install the Kubernetes GUI and manage KAITO workspaces visually.
{: .fs-6 .fw-300 }

<details open markdown="block">
  <summary>Table of contents</summary>
  {: .text-delta }
- TOC
{:toc}
</details>

---

## 6.1 What is Headlamp?

[Headlamp](https://headlamp.dev/) is a Kubernetes GUI dashboard. The **KAITO plugin** adds:

- Visual workspace management (create, monitor, delete)
- Real-time status indicators
- Model catalog browsing
- GPU node monitoring

---

## 6.2 Install Headlamp

### Windows (WSL users)

```bash
# Download latest Windows installer
HEADLAMP_VERSION=$(curl -s https://api.github.com/repos/headlamp-k8s/headlamp/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -LO "https://github.com/headlamp-k8s/headlamp/releases/download/v${HEADLAMP_VERSION}/Headlamp-${HEADLAMP_VERSION}-win-x64.exe"
```

### macOS

```bash
brew install --cask headlamp
```

### Linux

```bash
HEADLAMP_VERSION=$(curl -s https://api.github.com/repos/headlamp-k8s/headlamp/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -LO "https://github.com/headlamp-k8s/headlamp/releases/download/v${HEADLAMP_VERSION}/Headlamp-${HEADLAMP_VERSION}-linux-x64.AppImage"
chmod +x Headlamp-*-linux-x64.AppImage
sudo mv Headlamp-*-linux-x64.AppImage /usr/local/bin/headlamp
```

---

## 6.3 Install KAITO Plugin

1. Open Headlamp application
2. Click **Plugin Catalog** (puzzle icon in sidebar)
3. Search for **"Headlamp Kaito"**
4. Click **Install**
5. Click **Reload now**

---

## 6.4 Connect to Cluster

### For WSL users — copy kubeconfig to Windows

```bash
# Copy kubeconfig so Windows Headlamp can access the cluster
WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
cp ~/.kube/config /mnt/c/Users/${WIN_USER}/.kube/config
```

Then in Headlamp, select your cluster to connect.

---

## 6.5 Using KAITO in Headlamp

After installing the plugin, you'll see a **KAITO** section in the sidebar:

| Feature | Description |
|---------|-------------|
| **Kaito Workspaces** | List all workspaces, view status |
| **Create Workspace** | Deploy new models from the catalog |
| **Workspace Details** | See pods, events, conditions |
| **Model Catalog** | Browse available models |

---

[← Deploy Model]({{ site.baseurl }}{% link modules/05-deploy-model.md %}){: .btn .mr-2 }
[Next: Test Inference →]({{ site.baseurl }}{% link modules/07-test-inference.md %}){: .btn .btn-primary }
