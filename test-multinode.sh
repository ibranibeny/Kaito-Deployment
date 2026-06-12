#!/bin/bash
#===============================================================================
# KAITO Multi-Node Test Script
# 
# PURPOSE:
#   Quick test script to validate KAITO workspace deployment and inference.
#   Run this after deploying your workspace to verify everything works.
#
# USAGE:
#   ./test-multinode.sh [workspace-name]
#
# EXAMPLES:
#   ./test-multinode.sh                     # Uses default workspace-gpt-oss-20b
#   ./test-multinode.sh workspace-phi-4     # Test specific workspace
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default workspace name
WORKSPACE_NAME="${1:-workspace-gpt-oss-20b}"
MODEL_NAME="${2:-gpt-oss-20b}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  KAITO Multi-Node Test Script${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Workspace:${NC} ${WORKSPACE_NAME}"
echo -e "${YELLOW}Model:${NC} ${MODEL_NAME}"
echo ""

#===============================================================================
# TEST 1: Check Workspace Status
#===============================================================================
echo -e "${BLUE}[TEST 1] Checking Workspace Status${NC}"
echo "─────────────────────────────────────────────────────────────────"

# Get workspace conditions
echo "Workspace conditions:"
kubectl get workspace ${WORKSPACE_NAME} -o jsonpath='{range .status.conditions[*]}  {.type}: {.status} ({.reason}){"\n"}{end}' 2>/dev/null || {
    echo -e "${RED}ERROR: Workspace '${WORKSPACE_NAME}' not found${NC}"
    exit 1
}

# Check if InferenceReady
INFERENCE_READY=$(kubectl get workspace ${WORKSPACE_NAME} -o jsonpath='{.status.conditions[?(@.type=="InferenceReady")].status}' 2>/dev/null)

if [ "$INFERENCE_READY" != "True" ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Workspace not ready yet. InferenceReady=${INFERENCE_READY}${NC}"
    echo ""
    echo "Current pods:"
    kubectl get pods -l kaito.sh/workspace=${WORKSPACE_NAME} 2>/dev/null || \
        kubectl get pods | grep -E "(${WORKSPACE_NAME}|gpt-oss)" || \
        echo "No pods found"
    echo ""
    echo "Wait for InferenceReady=True before testing inference."
    echo "Monitor with: kubectl get workspace ${WORKSPACE_NAME} -w"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Workspace is ready!${NC}"
echo ""

#===============================================================================
# TEST 2: Check Pods
#===============================================================================
echo -e "${BLUE}[TEST 2] Checking Model Pods${NC}"
echo "─────────────────────────────────────────────────────────────────"

kubectl get pods -o wide | grep -E "(NAME|${MODEL_NAME})" || {
    echo -e "${YELLOW}No pods with label matching ${MODEL_NAME} found${NC}"
    kubectl get pods -o wide
}
echo ""

#===============================================================================
# TEST 3: Check Service
#===============================================================================
echo -e "${BLUE}[TEST 3] Checking Service${NC}"
echo "─────────────────────────────────────────────────────────────────"

SERVICE_NAME="svc/${WORKSPACE_NAME}"
kubectl get ${SERVICE_NAME} 2>/dev/null || {
    echo -e "${RED}ERROR: Service '${WORKSPACE_NAME}' not found${NC}"
    exit 1
}
echo ""

#===============================================================================
# TEST 4: Port Forward and Test Endpoint
#===============================================================================
echo -e "${BLUE}[TEST 4] Testing Inference Endpoint${NC}"
echo "─────────────────────────────────────────────────────────────────"

# Start port-forward in background
echo "Starting port-forward to ${SERVICE_NAME}..."
kubectl port-forward ${SERVICE_NAME} 8080:80 &>/dev/null &
PF_PID=$!

# Ensure cleanup on exit
cleanup() {
    echo ""
    echo "Cleaning up port-forward..."
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

# Wait for port-forward to establish
sleep 3

# Check if port-forward is working
if ! kill -0 $PF_PID 2>/dev/null; then
    echo -e "${RED}ERROR: Port-forward failed to start${NC}"
    exit 1
fi

echo -e "${GREEN}Port-forward active on localhost:8080${NC}"
echo ""

#-------------------------------------------------------------------------------
# Test 4a: Health Check
#-------------------------------------------------------------------------------
echo -e "${YELLOW}4a. Health Check:${NC}"
HEALTH_RESPONSE=$(curl -s http://localhost:8080/health 2>/dev/null || echo "FAILED")
echo "Response: ${HEALTH_RESPONSE}"
echo ""

#-------------------------------------------------------------------------------
# Test 4b: List Models
#-------------------------------------------------------------------------------
echo -e "${YELLOW}4b. List Models:${NC}"
MODELS_RESPONSE=$(curl -s http://localhost:8080/v1/models 2>/dev/null || echo "FAILED")
if command -v jq &> /dev/null; then
    echo "$MODELS_RESPONSE" | jq . 2>/dev/null || echo "$MODELS_RESPONSE"
else
    echo "$MODELS_RESPONSE"
fi
echo ""

#-------------------------------------------------------------------------------
# Test 4c: Simple Completion
#-------------------------------------------------------------------------------
echo -e "${YELLOW}4c. Chat Completion Test:${NC}"
echo "Prompt: 'What is Kubernetes in one sentence?'"
echo ""

CHAT_RESPONSE=$(curl -s -X POST http://localhost:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"${MODEL_NAME}\",
        \"messages\": [
            {\"role\": \"user\", \"content\": \"What is Kubernetes in one sentence?\"}
        ],
        \"max_tokens\": 100,
        \"temperature\": 0.7
    }" 2>/dev/null || echo "FAILED")

echo "Response:"
if command -v jq &> /dev/null; then
    echo "$CHAT_RESPONSE" | jq . 2>/dev/null || echo "$CHAT_RESPONSE"
else
    echo "$CHAT_RESPONSE"
fi
echo ""

# Extract just the content if jq is available
if command -v jq &> /dev/null; then
    CONTENT=$(echo "$CHAT_RESPONSE" | jq -r '.choices[0].message.content' 2>/dev/null)
    if [ "$CONTENT" != "null" ] && [ -n "$CONTENT" ]; then
        echo -e "${GREEN}Assistant Response:${NC}"
        echo "$CONTENT"
        echo ""
    fi
fi

#===============================================================================
# TEST 5: Latency Test (Optional)
#===============================================================================
echo -e "${BLUE}[TEST 5] Simple Latency Test${NC}"
echo "─────────────────────────────────────────────────────────────────"

echo "Running 3 requests to measure response time..."
echo ""

for i in 1 2 3; do
    START_TIME=$(date +%s.%N)
    
    curl -s -X POST http://localhost:8080/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${MODEL_NAME}\",
            \"messages\": [{\"role\": \"user\", \"content\": \"Say hello\"}],
            \"max_tokens\": 10
        }" > /dev/null 2>&1
    
    END_TIME=$(date +%s.%N)
    DURATION=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "N/A")
    
    echo "  Request $i: ${DURATION}s"
done
echo ""

#===============================================================================
# Summary
#===============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  TEST SUMMARY${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Workspace:       ${WORKSPACE_NAME}"
echo -e "  Model:           ${MODEL_NAME}"
echo -e "  InferenceReady:  ${GREEN}True${NC}"
echo -e "  Health:          ${HEALTH_RESPONSE}"
echo ""
echo -e "${YELLOW}Manual Testing Commands:${NC}"
echo ""
echo "  # Port forward (keep running in terminal)"
echo "  kubectl port-forward ${SERVICE_NAME} 8080:80"
echo ""
echo "  # Chat completion"
echo "  curl -X POST http://localhost:8080/v1/chat/completions \\"
echo '    -H "Content-Type: application/json" \'
echo "    -d '{\"model\":\"${MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}'"
echo ""
echo -e "${YELLOW}Headlamp:${NC}"
echo "  Open Headlamp → KAITO → Chat → Select workspace → Go"
echo ""

# Cleanup is handled by trap
echo -e "${GREEN}Tests complete!${NC}"
