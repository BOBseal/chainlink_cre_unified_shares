#!/bin/bash
#
# Vault Deployment & CRE Setup Helper Script
# 
# This script provides convenient commands for deploying and managing
# the Vault contract with CRE integration.
#
# Usage:
#   ./vault-deploy.sh [command] [options]
#
# Commands:
#   deploy         Deploy the Vault contract
#   setup          Configure CRE permissions
#   verify         Verify contract on Etherscan (requires ETHERSCAN_KEY)
#   status         Check Vault configuration
#   update-forwarder  Update Keystone Forwarder address
#
# Examples:
#   ./vault-deploy.sh deploy
#   ./vault-deploy.sh setup --workflow-id 0x...
#   ./vault-deploy.sh status --vault 0x...
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RPC_URL="${RPC_URL:-https://sepolia.infura.io/v3/YOUR_INFURA_KEY}"
NETWORK="${NETWORK:-sepolia}"

# Forwarder addresses
SEPOLIA_MOCK_FORWARDER="0x15fC6ae953E024d975e77382eEeC56A9101f9F88"
SEPOLIA_KEYSTONE_FORWARDER="0xF8344CFd5c43616a4366C34E3EEE75af79a74482"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

check_env() {
    if [ -z "$1" ]; then
        print_error "$2"
        exit 1
    fi
}

# ============================================================================
# Commands
# ============================================================================

cmd_deploy() {
    print_header "Deploying Vault Contract"
    
    # Check for required environment variables
    check_env "$PRIVATE_KEY" "PRIVATE_KEY not set. Export your private key: export PRIVATE_KEY=0x..."
    check_env "$RPC_URL" "RPC_URL not set. Export RPC URL: export RPC_URL=https://..."
    
    print_info "Network: $NETWORK"
    print_info "RPC URL: $RPC_URL"
    print_info ""
    
    # Run deployment
    if forge script "$SCRIPT_DIR/DeployVault.s.sol:DeployVault" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY" \
        --broadcast \
        -vvv; then
        print_success "Vault deployed successfully"
    else
        print_error "Deployment failed"
        exit 1
    fi
}

cmd_setup() {
    print_header "Setting Up CRE Permissions"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vault)
                VAULT_ADDRESS="$2"
                shift 2
                ;;
            --workflow-id)
                WORKFLOW_ID="$2"
                shift 2
                ;;
            --workflow-author)
                WORKFLOW_AUTHOR="$2"
                shift 2
                ;;
            --workflow-name)
                WORKFLOW_NAME="$2"
                shift 2
                ;;
            --forwarder)
                FORWARDER_ADDRESS="$2"
                shift 2
                ;;
            --use-mock)
                USE_MOCK_FORWARDER=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate vault address
    check_env "$VAULT_ADDRESS" "Vault address not provided. Use --vault 0x..."
    check_env "$PRIVATE_KEY" "PRIVATE_KEY not set"
    check_env "$RPC_URL" "RPC_URL not set"
    
    # Set forwarder based on environment
    if [ "$USE_MOCK_FORWARDER" == "true" ]; then
        FORWARDER_ADDRESS="${FORWARDER_ADDRESS:-$SEPOLIA_MOCK_FORWARDER}"
        print_info "Using MockForwarder: $FORWARDER_ADDRESS"
    else
        FORWARDER_ADDRESS="${FORWARDER_ADDRESS:-$SEPOLIA_KEYSTONE_FORWARDER}"
        print_info "Using KeystoneForwarder: $FORWARDER_ADDRESS"
    fi
    
    print_info "Vault Address: $VAULT_ADDRESS"
    [ -n "$WORKFLOW_ID" ] && print_info "Workflow ID: $WORKFLOW_ID"
    [ -n "$WORKFLOW_AUTHOR" ] && print_info "Workflow Author: $WORKFLOW_AUTHOR"
    [ -n "$WORKFLOW_NAME" ] && print_info "Workflow Name: $WORKFLOW_NAME"
    print_info ""
    
    # Run setup script
    if VAULT_ADDRESS="$VAULT_ADDRESS" \
       FORWARDER_ADDRESS="$FORWARDER_ADDRESS" \
       WORKFLOW_ID="${WORKFLOW_ID:-}" \
       WORKFLOW_AUTHOR="${WORKFLOW_AUTHOR:-}" \
       WORKFLOW_NAME="${WORKFLOW_NAME:-}" \
       USE_MOCK_FORWARDER="$USE_MOCK_FORWARDER" \
       forge script "$SCRIPT_DIR/SetupVaultCRE.s.sol:SetupVaultCRE" \
           --rpc-url "$RPC_URL" \
           --private-key "$PRIVATE_KEY" \
           --broadcast \
           -vvv; then
        print_success "CRE setup completed"
    else
        print_error "Setup failed"
        exit 1
    fi
}

cmd_verify() {
    print_header "Verifying Contract on Etherscan"
    
    if [ -z "$ETHERSCAN_KEY" ]; then
        print_warning "ETHERSCAN_KEY not set. Skipping verification."
        print_info "To verify, set: export ETHERSCAN_KEY=your_api_key"
        exit 0
    fi
    
    check_env "$CONTRACT_ADDRESS" "Contract address not provided. Use: export CONTRACT_ADDRESS=0x..."
    
    print_info "Contract Address: $CONTRACT_ADDRESS"
    
    forge verify-contract \
        "$CONTRACT_ADDRESS" \
        src/Vault.sol:Vault \
        --etherscan-api-key "$ETHERSCAN_KEY" \
        --chain "$NETWORK" \
        "ipfs://" \
        "$SEPOLIA_KEYSTONE_FORWARDER"
    
    print_success "Verification submitted"
}

cmd_status() {
    print_header "Vault Configuration Status"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vault)
                VAULT_ADDRESS="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_env "$VAULT_ADDRESS" "Vault address not provided. Use --vault 0x..."
    check_env "$RPC_URL" "RPC_URL not set"
    
    print_info "Checking configuration for Vault at: $VAULT_ADDRESS"
    print_info ""
    
    echo "Forwarder Address:"
    cast call "$VAULT_ADDRESS" "getForwarderAddress()" --rpc-url "$RPC_URL"
    echo ""
    
    echo "Expected Author:"
    cast call "$VAULT_ADDRESS" "getExpectedAuthor()" --rpc-url "$RPC_URL"
    echo ""
    
    echo "Expected Workflow ID:"
    cast call "$VAULT_ADDRESS" "getExpectedWorkflowId()" --rpc-url "$RPC_URL"
    echo ""
    
    echo "Contract Owner:"
    cast call "$VAULT_ADDRESS" "owner()" --rpc-url "$RPC_URL"
    echo ""
    
    print_success "Status check completed"
}

cmd_update_forwarder() {
    print_header "Updating Keystone Forwarder"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vault)
                VAULT_ADDRESS="$2"
                shift 2
                ;;
            --forwarder)
                NEW_FORWARDER="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_env "$VAULT_ADDRESS" "Vault address not provided. Use --vault 0x..."
    check_env "$NEW_FORWARDER" "New forwarder address not provided. Use --forwarder 0x..."
    check_env "$PRIVATE_KEY" "PRIVATE_KEY not set"
    
    print_info "Vault Address: $VAULT_ADDRESS"
    print_info "New Forwarder: $NEW_FORWARDER"
    print_warning "This will update the forwarder address for the Vault contract"
    
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        exit 0
    fi
    
    # Update forwarder using cast
    if cast send "$VAULT_ADDRESS" "setForwarderAddress(address)" "$NEW_FORWARDER" \
        --rpc-url "$RPC_URL" \
        --private-key "$PRIVATE_KEY"; then
        print_success "Forwarder address updated"
    else
        print_error "Update failed"
        exit 1
    fi
}

# ============================================================================
# Help
# ============================================================================

cmd_help() {
    cat << EOF
Vault Deployment & CRE Setup Helper

Usage:
  $0 [command] [options]

Commands:
  deploy              Deploy the Vault contract
  setup               Configure CRE permissions
  verify              Verify contract on Etherscan
  status              Check Vault configuration
  update-forwarder    Update Keystone Forwarder address
  help                Show this help message

Environment Variables:
  RPC_URL             RPC endpoint URL (default: Sepolia Infura)
  PRIVATE_KEY         Your private key for signing transactions
  NETWORK             Network name (default: sepolia)
  ETHERSCAN_KEY       Etherscan API key for verification

Examples:
  # Deploy Vault contract
  export RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
  export PRIVATE_KEY=0x...
  $0 deploy

  # Setup CRE permissions
  $0 setup --vault 0x... --workflow-author 0x...

  # Check Vault status
  $0 status --vault 0x...

  # Update to production forwarder
  $0 update-forwarder \
    --vault 0x... \
    --forwarder 0xF8344CFd5c43616a4366C34E3EEE75af79a74482

For more information, see DEPLOYMENT_GUIDE.md

EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        deploy)
            cmd_deploy "$@"
            ;;
        setup)
            cmd_setup "$@"
            ;;
        verify)
            cmd_verify "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        update-forwarder)
            cmd_update_forwarder "$@"
            ;;
        help|-h|--help)
            cmd_help
            ;;
        *)
            print_error "Unknown command: $command"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
