#!/usr/bin/env python3
"""
KAITO Multi-Node Inference - Streamlit Chat Interface

PURPOSE:
    Interactive web UI for testing KAITO-deployed models with configurable
    inference parameters (temperature, top_p, top_k) and real-time metrics.

FEATURES:
    - Chat interface with conversation history
    - Adjustable inference parameters (temperature, top_p, top_k)
    - Real-time tokens/second calculation
    - Model information display
    - OpenAI-compatible API integration

USAGE:
    # Install dependencies
    pip install streamlit requests

    # Port-forward KAITO service (run in separate terminal)
    kubectl port-forward svc/workspace-gpt-oss-20b 8080:80

    # Run Streamlit app
    streamlit run streamlit_app.py

ARCHITECTURE:
    ┌─────────────────────────────────────────────────────────────────┐
    │                    Streamlit Web Interface                       │
    │  ┌─────────────────────────────────────────────────────────┐    │
    │  │  Sidebar                  │  Main Chat Area             │    │
    │  │  - Model Info             │  - Conversation History     │    │
    │  │  - Temperature Slider     │  - User Input               │    │
    │  │  - Top-P Slider           │  - AI Responses             │    │
    │  │  - Top-K Slider           │  - Metrics (tokens/s)       │    │
    │  │  - Max Tokens             │                             │    │
    │  └─────────────────────────────────────────────────────────┘    │
    └─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
    ┌─────────────────────────────────────────────────────────────────┐
    │              KAITO Inference Service (localhost:8080)            │
    │              POST /v1/chat/completions                           │
    └─────────────────────────────────────────────────────────────────┘
"""

import streamlit as st
import requests
import json
import time
from datetime import datetime
from typing import Optional, Dict, Any, List

# =============================================================================
# CONFIGURATION
# =============================================================================
# Default API endpoint - assumes kubectl port-forward is running
DEFAULT_API_URL = "http://localhost:8080"

# Model configuration
DEFAULT_MODEL = "gpt-oss-20b"

# Default inference parameters
# These control the randomness and diversity of generated text
DEFAULT_TEMPERATURE = 0.7  # Higher = more random, Lower = more deterministic
DEFAULT_TOP_P = 0.9        # Nucleus sampling: consider tokens with cumulative prob <= top_p
DEFAULT_TOP_K = 50         # Only consider top K tokens for sampling
DEFAULT_MAX_TOKENS = 512   # Maximum tokens to generate

# =============================================================================
# API CLIENT
# =============================================================================
class KAITOClient:
    """
    Client for interacting with KAITO-deployed model inference endpoints.
    
    The API is OpenAI-compatible, supporting:
    - /v1/chat/completions: Chat-style completions
    - /v1/completions: Text completions
    - /v1/models: List available models
    - /health: Health check
    """
    
    def __init__(self, base_url: str = DEFAULT_API_URL):
        """
        Initialize the KAITO client.
        
        Args:
            base_url: Base URL of the KAITO inference service
                      Default: http://localhost:8080 (via port-forward)
        """
        self.base_url = base_url.rstrip("/")
        self.session = requests.Session()
        # Set reasonable timeout for LLM inference (can take time for long responses)
        self.timeout = 120  # seconds
    
    def health_check(self) -> Dict[str, Any]:
        """
        Check if the inference service is healthy.
        
        Returns:
            Health status response
        """
        try:
            response = self.session.get(
                f"{self.base_url}/health",
                timeout=10
            )
            return {"status": "healthy", "response": response.text}
        except requests.exceptions.RequestException as e:
            return {"status": "unhealthy", "error": str(e)}
    
    def list_models(self) -> List[str]:
        """
        Get list of available models from the inference service.
        
        Returns:
            List of model names
        """
        try:
            response = self.session.get(
                f"{self.base_url}/v1/models",
                timeout=10
            )
            if response.status_code == 200:
                data = response.json()
                return [m.get("id", "unknown") for m in data.get("data", [])]
            return [DEFAULT_MODEL]
        except:
            return [DEFAULT_MODEL]
    
    def chat_completion(
        self,
        messages: List[Dict[str, str]],
        model: str = DEFAULT_MODEL,
        temperature: float = DEFAULT_TEMPERATURE,
        top_p: float = DEFAULT_TOP_P,
        top_k: int = DEFAULT_TOP_K,
        max_tokens: int = DEFAULT_MAX_TOKENS,
    ) -> Dict[str, Any]:
        """
        Send a chat completion request to the KAITO inference service.
        
        This uses the OpenAI-compatible chat completions API format.
        
        Args:
            messages: List of message dicts with 'role' and 'content'
                     Roles: 'system', 'user', 'assistant'
            model: Model name to use
            temperature: Sampling temperature (0.0 - 2.0)
                        Higher = more random, Lower = more deterministic
            top_p: Nucleus sampling parameter (0.0 - 1.0)
                   Only consider tokens with cumulative probability <= top_p
            top_k: Top-K sampling parameter
                   Only consider the K most likely tokens
            max_tokens: Maximum number of tokens to generate
        
        Returns:
            Response dict with:
            - content: Generated text
            - tokens: Number of tokens generated
            - time_seconds: Time taken for inference
            - tokens_per_second: Throughput metric
            - error: Error message if failed
        """
        # Build request payload (OpenAI-compatible format)
        payload = {
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "top_p": top_p,
            "max_tokens": max_tokens,
            # Note: top_k may not be supported by all backends
            # vLLM supports it, but some may ignore it
        }
        
        # Add top_k if supported (vLLM extension)
        if top_k > 0:
            payload["top_k"] = top_k
        
        # Record start time for throughput calculation
        start_time = time.time()
        
        try:
            response = self.session.post(
                f"{self.base_url}/v1/chat/completions",
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=self.timeout
            )
            
            # Calculate elapsed time
            elapsed_time = time.time() - start_time
            
            if response.status_code == 200:
                data = response.json()
                
                # Extract response content
                choices = data.get("choices", [])
                if choices:
                    message = choices[0].get("message", {})
                    content = message.get("content", "")
                else:
                    content = ""
                
                # Extract token usage
                usage = data.get("usage", {})
                completion_tokens = usage.get("completion_tokens", len(content.split()))
                prompt_tokens = usage.get("prompt_tokens", 0)
                total_tokens = usage.get("total_tokens", completion_tokens + prompt_tokens)
                
                # Calculate tokens per second
                tokens_per_second = completion_tokens / elapsed_time if elapsed_time > 0 else 0
                
                return {
                    "success": True,
                    "content": content,
                    "completion_tokens": completion_tokens,
                    "prompt_tokens": prompt_tokens,
                    "total_tokens": total_tokens,
                    "time_seconds": elapsed_time,
                    "tokens_per_second": tokens_per_second,
                    "model": data.get("model", model),
                }
            else:
                return {
                    "success": False,
                    "error": f"HTTP {response.status_code}: {response.text}",
                    "time_seconds": elapsed_time,
                }
                
        except requests.exceptions.Timeout:
            return {
                "success": False,
                "error": "Request timed out. The model may be overloaded.",
                "time_seconds": time.time() - start_time,
            }
        except requests.exceptions.ConnectionError:
            return {
                "success": False,
                "error": "Connection failed. Is port-forward running?\n"
                        "Run: kubectl port-forward svc/workspace-gpt-oss-20b 8080:80",
                "time_seconds": time.time() - start_time,
            }
        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "time_seconds": time.time() - start_time,
            }

# =============================================================================
# STREAMLIT UI
# =============================================================================
def init_session_state():
    """
    Initialize Streamlit session state for persistent data across reruns.
    
    Session state stores:
    - messages: Chat conversation history
    - client: KAITO API client instance
    - metrics: Performance metrics from last request
    """
    if "messages" not in st.session_state:
        st.session_state.messages = []
    
    if "client" not in st.session_state:
        st.session_state.client = KAITOClient()
    
    if "metrics" not in st.session_state:
        st.session_state.metrics = {
            "tokens_per_second": 0,
            "last_response_time": 0,
            "total_tokens": 0,
        }

def render_sidebar():
    """
    Render the sidebar with model info and inference parameters.
    
    Returns:
        Dict with current parameter values
    """
    st.sidebar.title("🤖 KAITO Inference")
    
    # ==========================================================================
    # Model Information Section
    # ==========================================================================
    st.sidebar.header("📊 Model Info")
    
    # Check service health
    health = st.session_state.client.health_check()
    if health["status"] == "healthy":
        st.sidebar.success("✅ Service Connected")
    else:
        st.sidebar.error("❌ Service Disconnected")
        st.sidebar.caption("Run: `kubectl port-forward svc/workspace-gpt-oss-20b 8080:80`")
    
    # Get available models
    models = st.session_state.client.list_models()
    selected_model = st.sidebar.selectbox(
        "Model",
        options=models,
        index=0,
        help="Select the AI model to use for inference"
    )
    
    # Display model details
    st.sidebar.markdown(f"""
    **Current Model:** `{selected_model}`
    
    **Model Specs (gpt-oss-20b):**
    - Parameters: ~20B
    - Context: 128K tokens
    - Memory: ~16GB GPU
    """)
    
    # ==========================================================================
    # Performance Metrics Section
    # ==========================================================================
    st.sidebar.header("⚡ Performance")
    
    metrics = st.session_state.metrics
    
    col1, col2 = st.sidebar.columns(2)
    with col1:
        st.metric(
            "Tokens/sec",
            f"{metrics['tokens_per_second']:.1f}",
            help="Generation throughput (tokens per second)"
        )
    with col2:
        st.metric(
            "Response Time",
            f"{metrics['last_response_time']:.2f}s",
            help="Time for last response"
        )
    
    st.sidebar.metric(
        "Total Tokens",
        metrics['total_tokens'],
        help="Total tokens in last exchange (prompt + completion)"
    )
    
    st.sidebar.divider()
    
    # ==========================================================================
    # Inference Parameters Section
    # ==========================================================================
    st.sidebar.header("⚙️ Inference Parameters")
    
    # Temperature slider
    # Controls randomness in token selection
    # Lower values make output more deterministic
    temperature = st.sidebar.slider(
        "Temperature",
        min_value=0.0,
        max_value=2.0,
        value=DEFAULT_TEMPERATURE,
        step=0.1,
        help="""
        Controls randomness in generation:
        - 0.0: Deterministic (always picks most likely token)
        - 0.7: Balanced creativity and coherence (default)
        - 1.0+: More creative/random
        - 2.0: Maximum randomness
        """
    )
    
    # Top-P (nucleus sampling) slider
    # Only considers tokens with cumulative probability <= top_p
    top_p = st.sidebar.slider(
        "Top-P (Nucleus Sampling)",
        min_value=0.0,
        max_value=1.0,
        value=DEFAULT_TOP_P,
        step=0.05,
        help="""
        Nucleus sampling parameter:
        - Considers smallest set of tokens whose cumulative probability exceeds top_p
        - 0.9: Consider tokens until 90% cumulative probability (default)
        - 1.0: Consider all tokens
        - Lower values = more focused, higher values = more diverse
        """
    )
    
    # Top-K slider
    # Only considers the K most likely tokens
    top_k = st.sidebar.slider(
        "Top-K",
        min_value=1,
        max_value=100,
        value=DEFAULT_TOP_K,
        step=1,
        help="""
        Only consider the K most likely next tokens:
        - 1: Greedy decoding (always pick most likely)
        - 50: Consider top 50 tokens (default)
        - 100: More diverse options
        """
    )
    
    # Max tokens slider
    max_tokens = st.sidebar.slider(
        "Max Tokens",
        min_value=32,
        max_value=2048,
        value=DEFAULT_MAX_TOKENS,
        step=32,
        help="Maximum number of tokens to generate in response"
    )
    
    st.sidebar.divider()
    
    # ==========================================================================
    # Actions Section
    # ==========================================================================
    if st.sidebar.button("🗑️ Clear Chat", use_container_width=True):
        st.session_state.messages = []
        st.rerun()
    
    # API endpoint configuration
    with st.sidebar.expander("🔧 API Settings"):
        api_url = st.text_input(
            "API Endpoint",
            value=DEFAULT_API_URL,
            help="KAITO inference service URL"
        )
        if api_url != st.session_state.client.base_url:
            st.session_state.client = KAITOClient(api_url)
    
    return {
        "model": selected_model,
        "temperature": temperature,
        "top_p": top_p,
        "top_k": top_k,
        "max_tokens": max_tokens,
    }

def render_chat(params: Dict[str, Any]):
    """
    Render the main chat interface.
    
    Args:
        params: Inference parameters from sidebar
    """
    st.title("💬 KAITO Multi-Node Chat")
    st.caption(f"Model: **{params['model']}** | Region: **Indonesia Central** | GPU: **3x A10 (8GB each)**")
    
    # Display chat history
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])
            
            # Show metrics for assistant messages
            if message["role"] == "assistant" and "metrics" in message:
                metrics = message["metrics"]
                cols = st.columns(4)
                with cols[0]:
                    st.caption(f"⏱️ {metrics.get('time', 0):.2f}s")
                with cols[1]:
                    st.caption(f"⚡ {metrics.get('tps', 0):.1f} tok/s")
                with cols[2]:
                    st.caption(f"📊 {metrics.get('tokens', 0)} tokens")
                with cols[3]:
                    st.caption(f"🤖 {metrics.get('model', params['model'])}")
    
    # Chat input
    if prompt := st.chat_input("Type your message..."):
        # Add user message to history
        st.session_state.messages.append({
            "role": "user",
            "content": prompt
        })
        
        # Display user message
        with st.chat_message("user"):
            st.markdown(prompt)
        
        # Generate response
        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                # Build messages for API (include conversation history)
                api_messages = [
                    {"role": m["role"], "content": m["content"]}
                    for m in st.session_state.messages
                ]
                
                # Call KAITO API
                response = st.session_state.client.chat_completion(
                    messages=api_messages,
                    model=params["model"],
                    temperature=params["temperature"],
                    top_p=params["top_p"],
                    top_k=params["top_k"],
                    max_tokens=params["max_tokens"],
                )
                
                if response["success"]:
                    content = response["content"]
                    st.markdown(content)
                    
                    # Display metrics
                    cols = st.columns(4)
                    with cols[0]:
                        st.caption(f"⏱️ {response['time_seconds']:.2f}s")
                    with cols[1]:
                        st.caption(f"⚡ {response['tokens_per_second']:.1f} tok/s")
                    with cols[2]:
                        st.caption(f"📊 {response['total_tokens']} tokens")
                    with cols[3]:
                        st.caption(f"🤖 {response.get('model', params['model'])}")
                    
                    # Update session state
                    st.session_state.messages.append({
                        "role": "assistant",
                        "content": content,
                        "metrics": {
                            "time": response["time_seconds"],
                            "tps": response["tokens_per_second"],
                            "tokens": response["total_tokens"],
                            "model": response.get("model", params["model"]),
                        }
                    })
                    
                    # Update sidebar metrics
                    st.session_state.metrics = {
                        "tokens_per_second": response["tokens_per_second"],
                        "last_response_time": response["time_seconds"],
                        "total_tokens": response["total_tokens"],
                    }
                else:
                    st.error(f"❌ Error: {response['error']}")

def main():
    """
    Main entry point for the Streamlit application.
    """
    # Page configuration
    st.set_page_config(
        page_title="KAITO Multi-Node Chat",
        page_icon="🤖",
        layout="wide",
        initial_sidebar_state="expanded",
    )
    
    # Initialize session state
    init_session_state()
    
    # Render sidebar and get parameters
    params = render_sidebar()
    
    # Render main chat interface
    render_chat(params)

if __name__ == "__main__":
    main()
