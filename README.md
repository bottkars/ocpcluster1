# OpenShift Install

patching operator:
oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'

oc patch cloudcredential cluster --type json -p '[{"op": "add", "path": "/metadata/annotations", "value": { "upgradeable-to": "4.12.0" }}]'# ocpcluster1
# ocpcluster1
