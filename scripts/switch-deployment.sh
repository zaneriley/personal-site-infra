#!/bin/bash

#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m' # No Color


cat << EOF
=== Switch Deployment Script ===

This script is designed to test your local setup by simulating a blue/green deployment switch.

⚠️ This script is for local testing only. DO NOT use in production environments.
Proceed with caution. Press Ctrl+C to cancel, or any key to continue...
EOF

read -n 1 -s -r -p ""
echo ""

echo -e "${BOLD}Proceeding with the blue/green deployment switch...${NC}\n"

# Fetch the current backend service
if ! current_backend=$(kubectl get ingress personal-site -n personal-site -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'); then
    echo -e "${RED}Failed to fetch current backend service.${NC}"
    exit 1
else
    echo -e "${GREEN}1. Fetching current backend service... Done.${NC}"
    echo -e "   Current backend service: ${BOLD}$current_backend${NC}\n  "
fi

# Determine the new backend service
if [ "$current_backend" == "personal-site-blue" ]; then
  new_backend="personal-site-green"
else
  new_backend="personal-site-blue"
fi

# Update the main ingress
if kubectl patch ingress personal-site -n personal-site --type=json \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value":"'$new_backend'"}]'; then
    echo -e "${GREEN}2. Switching main traffic to alternate service... Done.${NC}"
    echo -e "   Traffic is now directed to: ${BOLD}$new_backend${NC}\n"
else
    echo -e "${RED}Failed to switch main traffic.${NC}"
    exit 1
fi

# Reset canary weight to 0
if kubectl patch ingress personal-site-canary -n personal-site -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"0"}}}'; then
    echo -e "${GREEN}3. Resetting canary weight to 0%... Done.${NC}"
    echo -e "   Canary traffic weight is now 0%.\n"
else
    echo -e "${RED}Failed to reset canary weight.${NC}"
    exit 1
fi

echo -e "${GREEN}All operations completed successfully.${NC}"
echo "Verify the deployment by checking ingress and pod statuses."