#!/bin/bash
#===============================================================================
# KAITO + Headlamp Demo Script (Simplified)
# GPU: Standard_NV36ads_A10_v5 (KAITO only supports NV36 and NV72 for A10)
#===============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
# STEP 1: Login
#===============================================================================
step1_login() {
    print_step "1" "Azure Login"
    az login --use-device-code
    az extension add --name aks-preview --upgrade || true
    print_success "Logged in!"
}

#===============================================================================
# STEP 2: Set Variables
#===============================================================================
step2_variables() {
    print_step "2" "Set Variables"
    
    export RAND=$RANDOM
    export LOCATION="${LOCATION:-indonesiacentral}"
    export RG_NAME="rg-kaito-demo-${RAND}"
    export AKS_NAME="aks-kaito-${RAND}"
    
    echo "RAND=${RAND}"
    echo "LOCATION=${LOCATION}"
    echo "RG_NAME=${RG_NAME}"
    echo "AKS_NAME=${AKS_NAME}"
    
    # Save to file
    cat > ./demo-env.sh << EOF
export RAND=${RAND}
export LOCATION=${LOCATION}
export RG_NAME=${RG_NAME}
export AKS_NAME=${AKS_NAME}
EOF
    
    print_success "Variables saved to demo-env.sh"
}

#===============================================================================
# STEP 3: Create Resource Group
#===============================================================================
step3_resource_group() {
    print_step "3" "Create Resource Group"
    if [ -f ./demo-env.sh ]; then source ./demo-env.sh; fi
    
    az group create --name $RG_NAME --location $LOCATION
    print_success "Resource group $RG_NAME created!"
}

#===============================================================================
# STEP 4: Create AKS with KAITO
#===============================================================================
step4_create_aks() {
    print_step "4" "Create AKS Cluster with KAITO"
    if [ -f ./demo-env.sh ]; then source ./demo-env.sh; fi
    
    print_info "Creating AKS cluster with KAITO enabled..."
    print_info "This takes about 10 minutes..."
    
    az aks create \
        --resource-group $RG_NAME \
        --name $AKS_NAME \
        --location $LOCATION \
        --node-count 1 \
        --node-vm-size Standard_D4s_v3 \
        --network-plugin azure \
        --network-plugin-mode overlay \
        --enable-managed-identity \
        --enable-oidc-issuer \
        --enable-ai-toolchain-operator \
        --generate-ssh-keys
    
    print_success "AKS cluster created with KAITO!"
}

#===============================================================================
# STEP 5: Get AKS Credentials
#===============================================================================
step5_get_credentials() {
    print_step "5" "Get AKS Credentials"
    if [ -f ./demo-env.sh ]; then source ./demo-env.sh; fi
    
    # Unset existing KUBECONFIG
    print_info "Unsetting existing KUBECONFIG..."
    unset KUBECONFIG
    
    # Set custom kubeconfig path
    KUBECONFIG_PATH="$HOME/.kube/config-kaito-${RAND}"
    
    print_info "Getting AKS credentials..."
    az aks get-credentials \
        --resource-group $RG_NAME \
        --name $AKS_NAME \
        --file $KUBECONFIG_PATH \
        --overwrite-existing
    
    # Export KUBECONFIG
    export KUBECONFIG=$KUBECONFIG_PATH
    
    # Save to demo-env.sh (update if exists, append if not)
    if grep -q "^export KUBECONFIG=" ./demo-env.sh 2>/dev/null; then
        sed -i "s|^export KUBECONFIG=.*|export KUBECONFIG=${KUBECONFIG_PATH}|" ./demo-env.sh
    else
        echo "export KUBECONFIG=${KUBECONFIG_PATH}" >> ./demo-env.sh
    fi
    
    print_info "KUBECONFIG exported to: $KUBECONFIG_PATH"
    print_info "Run: export KUBECONFIG=$KUBECONFIG_PATH"
    
    print_info "Verifying connection..."
    kubectl get nodes
    
    print_info "Verifying KAITO pods..."
    kubectl get pods -n kube-system | grep kaito || echo "KAITO pods starting..."
    
    print_success "Credentials configured!"
}

#===============================================================================
# STEP 6: Install Headlamp with KAITO Plugin
#===============================================================================
step6_install_headlamp() {
    print_step "6" "Install Headlamp with KAITO Plugin"
    
    # Detect OS
    OS=$(uname -s)
    
    case "$OS" in
        Linux*)
            print_info "Detected Linux/WSL"
            
            # Check if Headlamp is installed
            if command -v headlamp &> /dev/null; then
                print_info "Headlamp already installed"
            else
                print_info "Installing Headlamp..."
                
                # Download latest Headlamp AppImage
                HEADLAMP_VERSION=$(curl -s https://api.github.com/repos/headlamp-k8s/headlamp/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
                
                if [ -z "$HEADLAMP_VERSION" ]; then
                    HEADLAMP_VERSION="0.25.0"
                fi
                
                print_info "Downloading Headlamp v${HEADLAMP_VERSION}..."
                
                # For WSL, download Windows version
                if grep -qi microsoft /proc/version 2>/dev/null; then
                    print_info "WSL detected - downloading Windows installer..."
                    curl -LO "https://github.com/headlamp-k8s/headlamp/releases/download/v${HEADLAMP_VERSION}/Headlamp-${HEADLAMP_VERSION}-win-x64.exe"
                    
                    print_info "Windows installer downloaded: Headlamp-${HEADLAMP_VERSION}-win-x64.exe"
                    print_info "Run the installer from Windows Explorer"
                    
                    # Get Windows username (not WSL username)
                    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "$USER")
                    DOWNLOADS="/mnt/c/Users/${WIN_USER}/Downloads"
                    if [ -d "$DOWNLOADS" ]; then
                        mv "Headlamp-${HEADLAMP_VERSION}-win-x64.exe" "$DOWNLOADS/"
                        print_info "Moved to: $DOWNLOADS/Headlamp-${HEADLAMP_VERSION}-win-x64.exe"
                    fi
                else
                    # Linux native
                    curl -LO "https://github.com/headlamp-k8s/headlamp/releases/download/v${HEADLAMP_VERSION}/Headlamp-${HEADLAMP_VERSION}-linux-x64.AppImage"
                    chmod +x "Headlamp-${HEADLAMP_VERSION}-linux-x64.AppImage"
                    sudo mv "Headlamp-${HEADLAMP_VERSION}-linux-x64.AppImage" /usr/local/bin/headlamp
                    print_success "Headlamp installed to /usr/local/bin/headlamp"
                fi
            fi
            ;;
        Darwin*)
            print_info "Detected macOS"
            if command -v brew &> /dev/null; then
                brew install --cask headlamp
            else
                print_info "Download from: https://headlamp.dev/"
            fi
            ;;
        *)
            print_info "Download Headlamp from: https://headlamp.dev/"
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}After installing Headlamp:${NC}"
    echo "1. Open Headlamp application (Windows key -> search 'Headlamp')"
    echo "2. Click 'Plugin Catalog' (puzzle icon in sidebar)"
    echo "3. Search for 'Headlamp Kaito'"
    echo "4. Click 'Install'"
    echo "5. Click 'Reload now'"
    echo "6. Select your cluster to connect"
    echo ""
    
    # For WSL: copy kubeconfig to Windows
    if grep -qi microsoft /proc/version 2>/dev/null; then
        if [ -f ./demo-env.sh ]; then source ./demo-env.sh; fi
        if [ -n "$KUBECONFIG" ] && [ -f "$KUBECONFIG" ]; then
            WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r' || echo "$USER")
            WIN_KUBE_DIR="/mnt/c/Users/${WIN_USER}/.kube"
            mkdir -p "$WIN_KUBE_DIR" 2>/dev/null
            cp "$KUBECONFIG" "$WIN_KUBE_DIR/config"
            print_success "Kubeconfig copied to Windows: C:\\Users\\${WIN_USER}\\.kube\\config"
            echo ""
            echo -e "${GREEN}To open Headlamp from WSL:${NC}"
            echo "  cmd.exe /c start headlamp"
            echo ""
        fi
    else
        echo -e "${YELLOW}Make sure KUBECONFIG is set:${NC}"
        if [ -f ./demo-env.sh ]; then source ./demo-env.sh; fi
        echo "export KUBECONFIG=$KUBECONFIG"
    fi
    
    print_success "Headlamp setup complete!"
}

#===============================================================================
# STEP 7: Deploy Workspace
#===============================================================================
step7_deploy_workspace() {
    print_step "7" "Deploy KAITO Workspace"
    if [ -f ./demo-env.sh ]; then source ./demo-env.sh; fi
    
    print_info "Creating inference config ConfigMap..."
    cat << 'CONFIGMAP_EOF' | kubectl apply -f -
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
CONFIGMAP_EOF
    
    print_info "Applying workspace manifest..."
    kubectl apply -f workspace-phi4.yaml
    
    print_success "Workspace created!"
    print_info "Monitor progress with: kubectl get workspace -w"
    print_info "Or use Headlamp -> KAITO -> Kaito Workspaces"
    print_info "GPU node provisioning takes ~5-10 minutes"
    print_info "Model loading takes ~5 minutes after node is ready"
}

#===============================================================================
# STEP 8: Test Workspace
#===============================================================================
step8_test() {
    print_step "8" "Test Workspace"
    if [ -f ./demo-env.sh ]; then source ./demo-env.sh; fi
    
    # Check if jq is installed for JSON formatting
    if ! command -v jq &> /dev/null; then
        print_info "Installing jq for JSON formatting..."
        sudo apt-get update && sudo apt-get install -y jq 2>/dev/null || print_info "jq not installed, output will be raw JSON"
    fi
    
    print_info "Checking workspace status..."
    kubectl get workspace
    kubectl get pods
    
    # Check if workspace is ready
    INFERENCE_READY=$(kubectl get workspace workspace-phi-4-mini-instruct -o jsonpath='{.status.conditions[?(@.type=="InferenceReady")].status}' 2>/dev/null)
    
    if [ "$INFERENCE_READY" != "True" ]; then
        print_info "Workspace not ready yet. Current status:"
        kubectl describe workspace workspace-phi-4-mini-instruct | grep -A5 "Conditions:"
        echo ""
        print_info "Wait for INFERENCEREADY=True, then run this step again."
        print_info "Monitor with: kubectl get workspace -w"
        return
    fi
    
    print_success "Workspace is ready! Starting test..."
    
    # Port-forward in background
    print_info "Starting port-forward..."
    kubectl port-forward svc/workspace-phi-4-mini-instruct 8080:80 &>/dev/null &
    PF_PID=$!
    
    # Ensure cleanup on exit
    cleanup_port_forward() {
        kill $PF_PID 2>/dev/null
    }
    trap cleanup_port_forward EXIT
    
    sleep 3
    
    # Test the endpoint
    print_info "Testing chat completions endpoint..."
    echo ""
    
    RESPONSE=$(curl -s -X POST http://localhost:8080/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d '{"model":"phi-4-mini-instruct","messages":[{"role":"user","content":"What is Azure Kubernetes Service in one sentence?"}],"max_tokens":100}')
    
    if command -v jq &> /dev/null; then
        echo "$RESPONSE" | jq .
    else
        echo "$RESPONSE"
    fi
    
    echo ""
    print_success "Test complete!"
    
    # Cleanup port-forward
    print_info "Stopping port-forward..."
    trap - EXIT
    kill $PF_PID 2>/dev/null
    
    echo ""
    echo -e "${GREEN}Manual testing:${NC}"
    echo "  kubectl port-forward svc/workspace-phi-4-mini-instruct 8080:80"
    echo ""
    echo "  curl -X POST http://localhost:8080/v1/chat/completions \\"
    echo '    -H "Content-Type: application/json" \'
    echo '    -d '\''{"model":"phi-4-mini-instruct","messages":[{"role":"user","content":"Hello"}]}'\'
    echo ""
    echo -e "${GREEN}Or use Headlamp:${NC}"
    echo "  KAITO -> Chat -> Select workspace -> Go"
}

#===============================================================================
# STEP 9: Cleanup
#===============================================================================
step9_cleanup() {
    print_step "9" "Cleanup"
    if [ -f ./demo-env.sh ]; then source ./demo-env.sh; fi
    
    echo -e "${RED}Delete resource group $RG_NAME? (yes/no)${NC}"
    read CONFIRM
    
    if [ "$CONFIRM" = "yes" ]; then
        az group delete --name $RG_NAME --yes --no-wait
        
        # Remove kubeconfig
        if [ -n "$KUBECONFIG" ] && [ -f "$KUBECONFIG" ]; then
            rm -f "$KUBECONFIG"
            print_info "Removed kubeconfig: $KUBECONFIG"
        fi
        
        unset KUBECONFIG
        rm -f ./demo-env.sh
        print_success "Cleanup initiated!"
    else
        print_info "Cleanup cancelled."
    fi
}

#===============================================================================
# MENU
#===============================================================================
show_menu() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  KAITO + Headlamp Demo (Standard_NV36ads_A10_v5)${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  1) Azure Login"
    echo "  2) Set Variables"
    echo "  3) Create Resource Group"
    echo "  4) Create AKS with KAITO"
    echo "  5) Get AKS Credentials"
    echo "  6) Install Headlamp + KAITO Plugin"
    echo "  7) Deploy Workspace"
    echo "  8) Test Workspace"
    echo "  9) Cleanup"
    echo ""
    echo "  a) Run ALL (1-7)"
    echo "  q) Quit"
    echo ""
    printf "Choice: "
}

run_all() {
    step1_login; wait_for_user
    step2_variables; wait_for_user
    step3_resource_group; wait_for_user
    step4_create_aks; wait_for_user
    step5_get_credentials; wait_for_user
    step6_install_headlamp; wait_for_user
    step7_deploy_workspace
    print_success "All steps completed!"
}

main() {
    # Source env if exists
    if [ -f ./demo-env.sh ]; then source ./demo-env.sh; fi
    
    while true; do
        show_menu
        read choice
        case $choice in
            1) step1_login ;;
            2) step2_variables ;;
            3) step3_resource_group ;;
            4) step4_create_aks ;;
            5) step5_get_credentials ;;
            6) step6_install_headlamp ;;
            7) step7_deploy_workspace ;;
            8) step8_test ;;
            9) step9_cleanup ;;
            a|A) run_all ;;
            q|Q) echo "Bye!"; exit 0 ;;
            *) echo "Invalid option" ;;
        esac
        wait_for_user
    done
}

main
