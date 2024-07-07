#!/bin/bash

current_backend=$(kubectl get ingress personal-site -n personal-site -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')

if [ "$current_backend" == "personal-site-blue" ]; then
  new_backend="personal-site-green"
else
  new_backend="personal-site-blue"
fi

# Update the main ingress
kubectl patch ingress personal-site -n personal-site --type=json \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value":"'$new_backend'"}]'

# Update the canary ingress to point to the other service
kubectl patch ingress personal-site-canary -n personal-site --type=json \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value":"'"$current_backend"'"}]'

# Reset canary weight to 0
kubectl patch ingress personal-site-canary -n personal-site -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"0"}}}'

echo "Switched main traffic to $new_backend and reset canary"