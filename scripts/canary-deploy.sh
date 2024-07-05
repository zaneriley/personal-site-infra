#!/bin/bash

weight=$1

if [ -z "$weight" ]; then
  echo "Usage: $0 <weight>"
  exit 1
fi

# Update the canary ingress weight
kubectl patch ingress personal-site-canary -n personal-site -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"'$weight'"}}}'

echo "Canary deployment set to $weight%"

# If weight is 100, switch the main ingress to the canary version
if [ "$weight" -eq 100 ]; then
  current_backend=$(kubectl get ingress personal-site -n personal-site -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
  new_backend=$(kubectl get ingress personal-site-canary -n personal-site -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
  
  kubectl patch ingress personal-site -n personal-site --type=json \
    -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value":"'$new_backend'"}]'
  
  # Reset canary weight to 0
  kubectl patch ingress personal-site-canary -n personal-site -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"0"}}}'
  
  echo "Main traffic switched to $new_backend"
fi