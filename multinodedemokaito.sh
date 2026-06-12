#!/bin/bash
#===============================================================================
# KAITO Multi-Node Demo Script - GPT-OSS-20B with 3x A10 GPUs + llm-d
# 
# DEPLOYMENT CONFIGURATION:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  Parameter                    │ Value                                  │
# ├───────────────────────────────┼────────────────────────────────────────┤
# │  Region                       │ Indonesia Central                      │
# │  GPU VM SKU                   │ Standard_NV12ads_A10_v5                │
# │  GPU Type                     │ NVIDIA A10 (1/3 fractional, 8GB each) │
# │  Node Count                   │ 3 nodes                                │
# │  Total GPU Memory             │ 24GB (3 x 8GB)                         │
# │  Model                        │ gpt-oss-20b                            │
# │  Distribution Layer           │ llm-d (Prefill/Decode Disaggregation) │
# └─────────────────────────────────────────────────────────────────────────┘
#
# GPU SPECIFICATIONS - Standard_NV12ads_A10_v5:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  Component          │ Specification                                    │
# ├─────────────────────┼──────────────────────────────────────────────────┤
# │  vCPUs              │ 12                                               │
# │  RAM                │ 110 GiB                                          │
# │  GPU                │ 1/3 NVIDIA A10 (8GB GDDR6 - fractional)          │
# │  Temp Storage       │ 360 GiB SSD                                      │
# │  GPU Architecture   │ Ampere (GA102)                                   │
# │  FP16 Performance   │ ~10.4 TFLOPS (1/3 of 31.2)                       │
# └─────────────────────────────────────────────────────────────────────────┘
#
# llm-d ARCHITECTURE (Prefill/Decode Disaggregation):
# ┌─────────────────────────────────────────────────────────────────────────┐
# │                                                                         │
# │                    ┌─────────────────────────┐                          │
# │                    │   Inference Gateway     │                          │
# │                    │   (Envoy + Scheduler)   │                          │
# │                    │   - Prefix-cache aware  │                          │
# │                    │   - Load balancing      │                          │
# │                    │   - P/D routing         │                          │
# │                    └───────────┬─────────────┘                          │
# │                                │                                        │
# │              ┌─────────────────┼─────────────────┐                      │
# │              │                 │                 │                      │
# │              ▼                 ▼                 ▼                      │
# │  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐           │
# │  │    Node 1       │ │    Node 2       │ │    Node 3       │           │
# │  │  A10 GPU 8GB    │ │  A10 GPU 8GB    │ │  A10 GPU 8GB    │           │
# │  │  ┌───────────┐  │ │  ┌───────────┐  │ │  ┌───────────┐  │           │
# │  │  │  vLLM     │  │ │  │  vLLM     │  │ │  │  vLLM     │  │           │
# │  │  │ (Prefill) │  │ │  │ (Decode)  │  │ │  │ (Decode)  │  │           │
# │  │  └───────────┘  │ │  └───────────┘  │ │  └───────────┘  │           │
# │  └────────┬────────┘ └────────┬────────┘ └────────┬────────┘           │
# │           │                   │                   │                     │
# │           └───────────────────┼───────────────────┘                     │
# │                               │                                         │
# │                    ┌──────────┴──────────┐                              │
# │                    │  NIXL KV Transfer   │                              │
# │                    │  (Point-to-Point)   │                              │
# │                    └─────────────────────┘                              │
# │                                                                         │
# └─────────────────────────────────────────────────────────────────────────┘
#
# llm-d BENEFITS:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  Feature                      │ Benefit                                │
# ├───────────────────────────────┼────────────────────────────────────────┤
# │  Prefill/Decode Disaggregation│ Reduces Time-to-First-Token (TTFT)    │
# │  Intelligent Scheduling       │ Cache-aware, load-aware routing       │
# │  NIXL KV Cache Transfer       │ Efficient GPU-to-GPU cache sharing    │
# │  Kubernetes Native            │ CRDs, HPA, Prometheus metrics         │
# │  Wide Expert Parallelism      │ Optimal for MoE models                │
# └─────────────────────────────────────────────────────────────────────────┘
#
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}STEP $1: $2${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

wait_for_user() {
    echo ""
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read REPLY
}

#===============================================================================
# STEP 1: Azure Login
#===============================================================================
step1_login() {
    print_step "1" "Azure Login"
    
    print_info "Starting device code authentication..."
    az login --use-device-code
    
    print_info "Installing AKS preview extension..."
    az extension add --name aks-preview --upgrade || true
    
    print_info "Current subscription:"
    az account show --query "{Name:name, ID:id}" -o table
    
    print_success "Azure login completed!"
}

#===============================================================================
# STEP 2: Set Environment Variables
#===============================================================================
step2_variables() {
    print_step "2" "Set Environment Variables"
    
    export RAND="lab"
    export LOCATION="indonesiacentral"
    export RG_NAME="rg-kaito-multinode-${RAND}"
    export AKS_NAME="aks-kaito-mn-${RAND}"
    export NODE_COUNT=3
    export MODEL_NAME="gpt-oss-20b"
    export INSTANCE_TYPE="Standard_NV12ads_A10_v5"
    export GPU_MEMORY_GB=8
    
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              DEPLOYMENT CONFIGURATION                      ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Region:           ${GREEN}${LOCATION}${NC}"
    echo -e "${CYAN}║${NC}  Resource Group:   ${GREEN}${RG_NAME}${NC}"
    echo -e "${CYAN}║${NC}  AKS Cluster:      ${GREEN}${AKS_NAME}${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  GPU VM SKU:       ${GREEN}${INSTANCE_TYPE}${NC}"
    echo -e "${CYAN}║${NC}  GPU Type:         ${GREEN}NVIDIA A10 (1/3 fractional, 8GB)${NC}"
    echo -e "${CYAN}║${NC}  Node Count:       ${GREEN}${NODE_COUNT} nodes${NC}"
    echo -e "${CYAN}║${NC}  Total GPU Memory: ${GREEN}$((GPU_MEMORY_GB * NODE_COUNT))GB${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Model:            ${GREEN}${MODEL_NAME}${NC}"
    echo -e "${CYAN}║${NC}  Auth Required:    ${GREEN}No (public model)${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    
    cat > ./multinode-demo-env.sh << EOF
export RAND=${RAND}
export LOCATION=${LOCATION}
export RG_NAME=${RG_NAME}
export AKS_NAME=${AKS_NAME}
export NODE_COUNT=${NODE_COUNT}
export MODEL_NAME=${MODEL_NAME}
export INSTANCE_TYPE=${INSTANCE_TYPE}
export GPU_MEMORY_GB=${GPU_MEMORY_GB}
EOF
    
    print_success "Variables saved to multinode-demo-env.sh"
}

#===============================================================================
# STEP 3: Create Resource Group
#===============================================================================
step3_resource_group() {
    print_step "3" "Create Azure Resource Group"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    az group create --name $RG_NAME --location $LOCATION \
        --tags "purpose=kaito-demo" "model=${MODEL_NAME}"
    
    print_success "Resource group ${RG_NAME} created!"
}

#===============================================================================
# STEP 4: Create AKS with GPU Nodes
#===============================================================================
step4_create_aks() {
    print_step "4" "Create AKS Cluster with GPU Nodes"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    print_info "Creating AKS with ${NODE_COUNT}x A10 GPU nodes..."
    print_info "This takes 10-15 minutes..."
    
    az aks create \
        --resource-group $RG_NAME \
        --name $AKS_NAME \
        --location $LOCATION \
        --node-count $NODE_COUNT \
        --node-vm-size $INSTANCE_TYPE \
        --network-plugin azure \
        --network-plugin-mode overlay \
        --enable-managed-identity \
        --enable-oidc-issuer \
        --enable-ai-toolchain-operator \
        --generate-ssh-keys
    
    print_success "AKS cluster created with ${NODE_COUNT} GPU nodes!"
}

#===============================================================================
# STEP 5: Get Credentials
#===============================================================================
step5_get_credentials() {
    print_step "5" "Get AKS Credentials"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    unset KUBECONFIG
    KUBECONFIG_PATH="$HOME/.kube/config-kaito-multinode-${RAND}"
    
    az aks get-credentials \
        --resource-group $RG_NAME \
        --name $AKS_NAME \
        --file $KUBECONFIG_PATH \
        --overwrite-existing
    
    export KUBECONFIG=$KUBECONFIG_PATH
    echo "export KUBECONFIG=${KUBECONFIG_PATH}" >> ./multinode-demo-env.sh
    
    echo -e "${CYAN}Cluster Nodes:${NC}"
    kubectl get nodes -o wide
    
    # Copy to Windows if WSL
    if grep -qi microsoft /proc/version 2>/dev/null; then
        WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
        cp "$KUBECONFIG" "/mnt/c/Users/${WIN_USER}/.kube/config" 2>/dev/null || true
    fi
    
    print_success "Credentials configured!"
}

#===============================================================================
# STEP 6: Create Workspace YAML
#===============================================================================
step6_create_workspace_yaml() {
    print_step "6" "Create KAITO Workspace YAML"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    # KAITO Workspace YAML 
    # NOTE: KAITO Workspace does NOT use "spec:" - resource/inference are top-level fields
    # NOTE: gpt-oss-20b does NOT require modelAccessSecret (not a gated model)
    # Reference: https://github.com/kaito-project/kaito/blob/main/README.md
    cat > ./workspace-gpt-oss-20b-multinode.yaml << EOF
apiVersion: kaito.sh/v1beta1
kind: Workspace
metadata:
  name: workspace-gpt-oss-20b
  labels:
    app: gpt-oss-20b
resource:
  count: ${NODE_COUNT}
  instanceType: "${INSTANCE_TYPE}"
  labelSelector:
    matchLabels:
      apps: gpt-oss-20b
inference:
  preset:
    name: "${MODEL_NAME}"
EOF
    
    print_success "Workspace YAML created!"
    cat ./workspace-gpt-oss-20b-multinode.yaml
}

#===============================================================================
# STEP 7: Deploy Workspace
#===============================================================================
#===============================================================================
# STEP 7: Deploy Workspace
#===============================================================================
# NOTE: gpt-oss-20b is a public model and does NOT require HF_TOKEN authentication.
# For gated models (e.g., llama, gemma), you would need to add modelAccessSecret.
# See: https://github.com/kaito-project/kaito/blob/main/docs/proposals/20250529-llama-3.3-70b-instruct.md
step7_deploy_workspace() {
    print_step "7" "Deploy KAITO Workspace"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    print_info "Applying workspace..."
    kubectl apply -f workspace-gpt-oss-20b-multinode.yaml
    
    print_success "Workspace deployed!"
    print_info "Model download takes 5-15 minutes"
    print_info "Monitor: kubectl get workspace -w"
    
    echo ""
    echo -e "${CYAN}Check workspace status:${NC}"
    echo "  kubectl get workspace workspace-gpt-oss-20b -w"
    echo "  kubectl describe workspace workspace-gpt-oss-20b"
}

#===============================================================================
# STEP 8: Deploy Gateway API Inference Extension (Optional Advanced Feature)
#===============================================================================
# GATEWAY API INFERENCE EXTENSION EXPLANATION:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  The Gateway API Inference Extension provides advanced routing for     │
# │  LLM inference workloads. It adds CRDs like InferencePool and          │
# │  InferenceModel to Kubernetes for intelligent request routing.         │
# │                                                                         │
# │  NOTE: This is OPTIONAL. KAITO already creates a working service.      │
# │  Use this only if you need:                                            │
# │  - Prefix-cache aware routing                                          │
# │  - Load balancing across multiple backends                             │
# │  - Model criticality-based prioritization                              │
# │                                                                         │
# │  For basic inference, skip this step and use KAITO's service directly: │
# │  kubectl port-forward svc/workspace-gpt-oss-20b 8080:80                │
# └─────────────────────────────────────────────────────────────────────────┘
step8_deploy_llmd() {
    print_step "8" "Deploy Gateway API Inference Extension (Optional)"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    echo ""
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  Gateway API Inference Extension is an OPTIONAL feature   ║${NC}"
    echo -e "${YELLOW}║  that requires additional infrastructure setup.           ║${NC}"
    echo -e "${YELLOW}║                                                           ║${NC}"
    echo -e "${YELLOW}║  KAITO has already deployed your model with a service.    ║${NC}"
    echo -e "${YELLOW}║  You can start using it immediately with port-forward.    ║${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}Choose an option:${NC}"
    echo "  1) Skip - Use KAITO service directly (Recommended for quick start)"
    echo "  2) Install Gateway API Inference Extension CRDs only"
    echo "  3) Full llm-d setup (Requires cloning llm-d repo and helmfile)"
    echo ""
    read -p "Enter choice [1-3, default=1]: " CHOICE
    CHOICE=${CHOICE:-1}
    
    case $CHOICE in
        1)
            print_info "Skipping Gateway API Inference Extension..."
            print_info "You can access your model directly via KAITO's service"
            echo ""
            echo -e "${GREEN}Quick Start Commands:${NC}"
            echo "  # Port forward to access the model"
            echo "  kubectl port-forward svc/workspace-gpt-oss-20b 8080:80"
            echo ""
            echo "  # Test inference"
            echo '  curl http://localhost:8080/v1/completions \'
            echo '    -H "Content-Type: application/json" \'
            echo '    -d '"'"'{"model": "gpt-oss-20b", "prompt": "Hello", "max_tokens": 50}'"'"
            ;;
        2)
            print_info "Installing Gateway API Inference Extension CRDs..."
            
            # Gateway API CRDs (v1.2.0)
            print_info "Installing Gateway API v1.2.0 CRDs..."
            kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml || {
                print_error "Failed to install Gateway API CRDs"
                return 1
            }
            
            # Gateway API Inference Extension CRDs (v0.3.0)
            print_info "Installing Gateway API Inference Extension v0.3.0 CRDs..."
            kubectl apply -k https://github.com/kubernetes-sigs/gateway-api-inference-extension/config/crd?ref=v0.3.0 || {
                print_error "Failed to install Inference Extension CRDs"
                return 1
            }
            
            print_success "Gateway API Inference Extension CRDs installed!"
            echo ""
            echo -e "${CYAN}Available CRDs:${NC}"
            kubectl api-resources --api-group=inference.networking.x-k8s.io 2>/dev/null || \
            kubectl api-resources --api-group=inference.networking.k8s.io 2>/dev/null || \
                echo "CRDs are being registered..."
            
            echo ""
            echo -e "${YELLOW}NOTE: To use InferencePool/InferenceModel, you also need:${NC}"
            echo "  1. A Gateway provider (Istio, Kgateway, or GKE Gateway)"
            echo "  2. The Endpoint Picker (EPP) deployment"
            echo "  See: https://gateway-api-inference-extension.sigs.k8s.io/"
            ;;
        3)
            print_info "Full llm-d setup requires cloning the repository..."
            echo ""
            echo -e "${CYAN}Manual Steps for full llm-d setup:${NC}"
            echo ""
            echo "# 1. Clone llm-d repository"
            echo "git clone https://github.com/llm-d/llm-d.git"
            echo "cd llm-d"
            echo ""
            echo "# 2. Install client tools"
            echo "./guides/prereq/client-setup/install-deps.sh"
            echo ""
            echo "# 3. Install Gateway API CRDs"
            echo "cd guides/prereq/gateway-provider"
            echo "./install-gateway-provider-dependencies.sh"
            echo ""
            echo "# 4. Install Gateway provider (Istio)"
            echo "helmfile apply -f istio.helmfile.yaml"
            echo ""
            echo "# 5. Deploy llm-d inference scheduling"
            echo "cd ../inference-scheduling"
            echo "export NAMESPACE=llm-d"
            echo "kubectl create namespace \$NAMESPACE"
            echo "helmfile apply -n \$NAMESPACE"
            echo ""
            echo "See: https://github.com/llm-d/llm-d/tree/main/guides"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              KAITO + Inference Architecture               ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Client Request                                           ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}       │                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}       ▼                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ┌─────────────────────────────────┐                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  │  KAITO Service                  │                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  │  workspace-gpt-oss-20b:80       │                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  │  (ClusterIP - port-forward)     │                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  └─────────────────────────────────┘                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}       │                                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}       ├──────────────┬──────────────┐                     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}       ▼              ▼              ▼                     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   [Node 1]      [Node 2]      [Node 3]                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   A10 8GB       A10 8GB       A10 8GB                     ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   gpt-oss-20b   gpt-oss-20b   gpt-oss-20b                 ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

#===============================================================================
# STEP 9: Monitor Status
#===============================================================================
step9_monitor() {
    print_step "9" "Monitor Workspace Status"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    echo -e "${CYAN}Workspace:${NC}"
    kubectl get workspace workspace-gpt-oss-20b -o wide 2>/dev/null || echo "Not found"
    echo ""
    
    echo -e "${CYAN}Conditions:${NC}"
    kubectl get workspace workspace-gpt-oss-20b \
        -o jsonpath='{range .status.conditions[*]}  {.type}: {.status}{"\n"}{end}' 2>/dev/null
    echo ""
    
    echo -e "${CYAN}Pods:${NC}"
    kubectl get pods -l apps=gpt-oss-20b -o wide 2>/dev/null || echo "No pods yet"
    echo ""
    
    echo -e "${CYAN}llm-d Components:${NC}"
    kubectl get inferencepool,inferencemodel,gateway 2>/dev/null || echo "llm-d not deployed yet"
    echo ""
    
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}To run nvidia-smi on each GPU node:${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  # Run on all pods at once:"
    echo "  for pod in \$(kubectl get pods -l apps=gpt-oss-20b -o name); do"
    echo "    echo \"=== \$pod ===\""
    echo "    kubectl exec \$pod -- nvidia-smi"
    echo "  done"
    echo ""
    echo "  # Or run on a specific pod:"
    echo "  kubectl exec -it <pod-name> -- nvidia-smi"
}

#===============================================================================
# STEP 10: Streamlit UI
#===============================================================================
step10_streamlit() {
    print_step "10" "Streamlit Chat UI"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    if [ ! -f "./streamlit_app.py" ]; then
        print_error "streamlit_app.py not found!"
        return 1
    fi
    
    pip install streamlit requests --quiet 2>/dev/null
    
    READY=$(kubectl get workspace workspace-gpt-oss-20b \
        -o jsonpath='{.status.conditions[?(@.type=="InferenceReady")].status}' 2>/dev/null)
    
    if [ "$READY" != "True" ]; then
        print_info "Workspace not ready. Status:"
        kubectl get workspace workspace-gpt-oss-20b \
            -o jsonpath='{range .status.conditions[*]}  {.type}: {.status}{"\n"}{end}' 2>/dev/null
        echo ""
    fi
    
    echo -e "${CYAN}To start:${NC}"
    echo "  Terminal 1: kubectl port-forward svc/workspace-gpt-oss-20b 8080:80"
    echo "  Terminal 2: streamlit run streamlit_app.py"
    echo "  Browser:    http://localhost:8501"
    echo ""
    
    echo "Start now? (yes/no)"
    read START
    
    if [ "$START" = "yes" ]; then
        kubectl port-forward svc/workspace-gpt-oss-20b 8080:80 &>/dev/null &
        sleep 2
        streamlit run streamlit_app.py
    fi
}

#===============================================================================
# STEP 11: CLI Test
#===============================================================================
step11_test() {
    print_step "11" "CLI Test"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    READY=$(kubectl get workspace workspace-gpt-oss-20b \
        -o jsonpath='{.status.conditions[?(@.type=="InferenceReady")].status}' 2>/dev/null)
    
    if [ "$READY" != "True" ]; then
        print_info "Not ready. Run step 8 to check status."
        return
    fi
    
    kubectl port-forward svc/workspace-gpt-oss-20b 8080:80 &>/dev/null &
    PF_PID=$!
    trap "kill $PF_PID 2>/dev/null" EXIT
    sleep 3
    
    echo -e "${CYAN}Health:${NC}"
    curl -s http://localhost:8080/health
    echo ""
    
    echo -e "${CYAN}Chat Test:${NC}"
    curl -s -X POST http://localhost:8080/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model":"gpt-oss-20b","messages":[{"role":"user","content":"Hello"}],"max_tokens":50}' | \
        python3 -m json.tool 2>/dev/null || cat
    
    trap - EXIT
    kill $PF_PID 2>/dev/null
    print_success "Test complete!"
}

#===============================================================================
# STEP 12: Cleanup
#===============================================================================
step12_cleanup() {
    print_step "12" "Cleanup"
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    echo -e "${RED}Delete ${RG_NAME}? (yes/no)${NC}"
    read CONFIRM
    
    if [ "$CONFIRM" = "yes" ]; then
        az group delete --name $RG_NAME --yes --no-wait
        rm -f "$KUBECONFIG" ./workspace-gpt-oss-20b-multinode.yaml ./multinode-demo-env.sh
        rm -f ./llmd-inference-pool.yaml ./llmd-inference-model.yaml ./llmd-gateway.yaml
        print_success "Cleanup initiated!"
    fi
}

#===============================================================================
# MENU
#===============================================================================
show_menu() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     ${GREEN}KAITO + llm-d Multi-Node Demo${NC}                          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}     ${CYAN}Region: Indonesia Central | 3x A10 GPUs${NC}               ${BLUE}║${NC}"
    echo -e "${BLUE}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}Setup:${NC}                                                  ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    1) Azure Login                                         ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    2) Set Variables                                       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    3) Create Resource Group                               ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    4) Create AKS with GPU Nodes                           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    5) Get Credentials                                     ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}Deploy:${NC}                                                 ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    6) Create Workspace YAML                               ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    7) Deploy KAITO Workspace                              ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    8) Deploy llm-d Distribution Layer                     ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}    9) Monitor Status                                      ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}Test:${NC}                                                   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}   10) Streamlit Chat UI                                   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}   11) CLI Test                                            ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}Cleanup:${NC}                                                ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}   12) Delete All                                          ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}                                                           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}  ${GREEN}a) Run ALL (1-8)${NC}    ${RED}q) Quit${NC}                           ${BLUE}║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    printf "Choice: "
}

run_all() {
    step1_login; wait_for_user
    step2_variables; wait_for_user
    step3_resource_group; wait_for_user
    step4_create_aks; wait_for_user
    step5_get_credentials; wait_for_user
    step6_create_workspace_yaml; wait_for_user
    step7_deploy_workspace; wait_for_user
    step8_deploy_llmd
    print_success "Deployment complete! Use 9-11 to monitor and test."
}

main() {
    if [ -f ./multinode-demo-env.sh ]; then source ./multinode-demo-env.sh; fi
    
    while true; do
        show_menu
        read choice
        case $choice in
            1) step1_login ;;
            2) step2_variables ;;
            3) step3_resource_group ;;
            4) step4_create_aks ;;
            5) step5_get_credentials ;;
            6) step6_create_workspace_yaml ;;
            7) step7_deploy_workspace ;;
            8) step8_deploy_llmd ;;
            9) step9_monitor ;;
            10) step10_streamlit ;;
            11) step11_test ;;
            12) step12_cleanup ;;
            a|A) run_all ;;
            q|Q) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid" ;;
        esac
        wait_for_user
    done
}

main
