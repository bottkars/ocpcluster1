#!/bin/bash
ssh-add  ~/.ssh/id_openssh
echo "Populating Assets"
rm -rf ./assets
mkdir ./assets
cp backup/IPI_install-config.yaml assets/install-config.yaml
openshift-install create manifests --dir=assets
# cp ./backup/*cred*.yaml assets/manifests
INFRA_ID="$(jq '."*installconfig.ClusterID".InfraID' -r ./assets/.openshift_install_state.json)"
export INFRA_ID
export CLUSTER_NAME=ocpcluster1
echo "Infra ID is $INFRA_ID"

#cat > assets/manifests/cco-configmap.yaml <<EOF 
#apiVersion: v1
#kind: ConfigMap
#metadata:
#  name: cloud-credential-operator-config
#  namespace: openshift-cloud-credential-operator
#  annotations:
#    release.openshift.io/create-only: "true"
#data:
#  disabled: "true"
#EOF

cat > assets/manifests/cluster-proxy-01-config.yaml <<EOF
apiVersion: config.openshift.io/v1
kind: Proxy
metadata:
  creationTimestamp: null
  name: cluster
spec:
  trustedCA:
    name: user-ca-bundle
status: {}
EOF

cat > assets/manifests/azure-cloud-credentials-api.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: azure-cloud-credentials
  namespace: openshift-machine-api
stringData:
  azure_subscription_id: ${AZURE_SUBSCRIPTION_ID}
  azure_client_id: ${AZURE_CLIENT_ID}
  azure_client_secret: ${AZURE_CLIENT_SECRET}
  azure_tenant_id: ${AZURE_TENANT_ID}
  azure_resource_prefix: ${INFRA_ID}
  azure_resourcegroup: ${INFRA_ID}-rg
  azure_region: ${AZURE_REGION}
EOF

cat > assets/manifests/azure-cloud-credentials.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
    name: azure-cloud-credentials
    namespace: openshift-cloud-controller-manager
stringData:
  azure_subscription_id: ${AZURE_SUBSCRIPTION_ID}
  azure_client_id: ${AZURE_CLIENT_ID}
  azure_client_secret: ${AZURE_CLIENT_SECRET}
  azure_tenant_id: ${AZURE_TENANT_ID}
  azure_resource_prefix: ${INFRA_ID}
  azure_resourcegroup: ${INFRA_ID}-rg
  azure_region: ${AZURE_REGION}
EOF

cat > assets/manifests/azure-cloud-credentials-system.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
  name: azure-credentials
  namespace: kube-system
stringData:
  azure_subscription_id: ${AZURE_SUBSCRIPTION_ID}
  azure_client_id: ${AZURE_CLIENT_ID}
  azure_client_secret: ${AZURE_CLIENT_SECRET}
  azure_tenant_id: ${AZURE_TENANT_ID}
  azure_resource_prefix: ${INFRA_ID}
  azure_resourcegroup: ${INFRA_ID}-rg
  azure_region: ${AZURE_REGION}
EOF

cat > assets/manifests/azure-disk-credentials.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
    name: azure-disk-credentials
    namespace: openshift-cluster-csi-drivers
stringData:
  azure_subscription_id: ${AZURE_SUBSCRIPTION_ID}
  azure_client_id: ${AZURE_CLIENT_ID}
  azure_client_secret: ${AZURE_CLIENT_SECRET}
  azure_tenant_id: ${AZURE_TENANT_ID}
  azure_resource_prefix: ${INFRA_ID}
  azure_resourcegroup: ${INFRA_ID}-rg
  azure_region: ${AZURE_REGION}
EOF

cat > assets/manifests/azure-file-credentials.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
    name: azure-file-credentials
    namespace: openshift-cluster-csi-drivers
stringData:
  azure_subscription_id: ${AZURE_SUBSCRIPTION_ID}
  azure_client_id: ${AZURE_CLIENT_ID}
  azure_client_secret: ${AZURE_CLIENT_SECRET}
  azure_tenant_id: ${AZURE_TENANT_ID}
  azure_resource_prefix: ${INFRA_ID}
  azure_resourcegroup: ${INFRA_ID}-rg
  azure_region: ${AZURE_REGION}
EOF


cat > assets/manifests/cloud-credentials.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
    name: cloud-credentials
    namespace: openshift-ingress-operator
stringData:
  azure_subscription_id: ${AZURE_SUBSCRIPTION_ID}
  azure_client_id: ${AZURE_CLIENT_ID}
  azure_client_secret: ${AZURE_CLIENT_SECRET}
  azure_tenant_id: ${AZURE_TENANT_ID}
  azure_resource_prefix: ${INFRA_ID}
  azure_resourcegroup: ${INFRA_ID}-rg
  azure_region: ${AZURE_REGION}
EOF

cat > assets/manifests/cloud-network-config-controller.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
    name: cloud-credentials
    namespace: openshift-cloud-network-config-controller
stringData:
  azure_subscription_id: ${AZURE_SUBSCRIPTION_ID}
  azure_client_id: ${AZURE_CLIENT_ID}
  azure_client_secret: ${AZURE_CLIENT_SECRET}
  azure_tenant_id: ${AZURE_TENANT_ID}
  azure_resource_prefix: ${INFRA_ID}
  azure_resourcegroup: ${INFRA_ID}-rg
  azure_region: ${AZURE_REGION}
EOF

cat > assets/manifests/installer-cloud-credentials.yaml <<EOF 
apiVersion: v1
kind: Secret
metadata:
    name: installer-cloud-credentials
    namespace: openshift-image-registry
stringData:
  azure_subscription_id: ${AZURE_SUBSCRIPTION_ID}
  azure_client_id: ${AZURE_CLIENT_ID}
  azure_client_secret: ${AZURE_CLIENT_SECRET}
  azure_tenant_id: ${AZURE_TENANT_ID}
  azure_resource_prefix: ${INFRA_ID}
  azure_resourcegroup: ${INFRA_ID}-rg
  azure_region: ${AZURE_REGION}
EOF

#cat > assets/manifests/cluster-scheduler-02-config.yml <<EOF
#apiVersion: config.openshift.io/v1
#kind: Scheduler
#metadata:
#  creationTimestamp: null
#  name: cluster
#spec:
#  mastersSchedulable: false
#  policy:
#    name: ""
#status: {}
#EOF

#cat > assets/manifests/cluster-dns-02-config.yml <<EOF
#apiVersion: config.openshift.io/v1
#kind: DNS
#metadata:
#  creationTimestamp: null
#  name: cluster
#spec:
#  baseDomain: ${CLUSTER_NAME}.${BASE_DOMAIN}
#status: {}
#EOF

# cp backup/cco-configmap.yaml assets/manifests
#rm -f assets/openshift/99_openshift-cluster-api_master-machines-*.yaml
#rm -f assets/openshift/99_openshift-cluster-api_worker-machineset-*.yaml
# cp 000* assets/manifests/
openshift-install create cluster --dir assets --log-level=info
