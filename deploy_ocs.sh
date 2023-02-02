#!/bin/bash
echo "Deleting old Resource Group ${RESOURCE_GROUP}"
az group delete --name "${RESOURCE_GROUP}" -y
ssh-add  ~/.ssh/id_openssh
echo "Populating Assets"
rm -rf ./assets
mkdir ./assets
cp backup/install-config.yaml assets
openshift-install create manifests --dir=assets
# cp ./backup/*cred*.yaml assets/manifests
INFRA_ID="$(jq '."*installconfig.ClusterID".InfraID' -r ./assets/.openshift_install_state.json)"
export INFRA_ID
export CLUSTER_NAME=ocpcluster1
echo "Infra ID is $INFRA_ID"

cat > assets/manifests/cco-configmap.yaml <<EOF 
apiVersion: v1
kind: ConfigMap
metadata:
  name: cloud-credential-operator-config
  namespace: openshift-cloud-credential-operator
  annotations:
    release.openshift.io/create-only: "true"
data:
  disabled: "true"
EOF

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
  azure_resourcegroup: ${RESOURCE_GROUP}
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
  azure_resourcegroup: ${RESOURCE_GROUP}
  azure_region: ${AZURE_REGION}
EOF

cat >> assets/manifests/azure-cloud-credentials-system.yaml <<EOF 
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
  azure_resourcegroup: ${RESOURCE_GROUP}
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
  azure_resourcegroup: ${RESOURCE_GROUP}
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
  azure_resourcegroup: ${RESOURCE_GROUP}
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
  azure_resourcegroup: ${RESOURCE_GROUP}
  azure_region: ${AZURE_REGION}
EOF

cat > assets/manifests/cluster-scheduler-02-config.yml <<EOF
apiVersion: config.openshift.io/v1
kind: Scheduler
metadata:
  creationTimestamp: null
  name: cluster
spec:
  mastersSchedulable: false
  policy:
    name: ""
status: {}
EOF

cat > assets/manifests/cluster-dns-02-config.yml <<EOF
apiVersion: config.openshift.io/v1
kind: DNS
metadata:
  creationTimestamp: null
  name: cluster
spec:
  baseDomain: ${CLUSTER_NAME}.${BASE_DOMAIN}
status: {}
EOF

# cp backup/cco-configmap.yaml assets/manifests
rm -f assets/openshift/99_openshift-cluster-api_master-machines-*.yaml
rm -f assets/openshift/99_openshift-cluster-api_worker-machineset-*.yaml

echo "Creating Openshift Ignition Configs"
openshift-install create ignition-configs --dir=assets 
echo "Creating Deployment Resources"
az group create --name "${RESOURCE_GROUP}" --location "${AZURE_REGION}" \
--output table

az storage account create -g "${RESOURCE_GROUP}" \
--location "${AZURE_REGION}" --name "${CLUSTER_NAME}"sa --kind Storage \
--sku Standard_LRS \
--output table

ACCOUNT_KEY=$(az storage account keys list -g "${RESOURCE_GROUP}" \
--account-name "${CLUSTER_NAME}"sa --query "[0].value" -o tsv)
export ACCOUNT_KEY
az storage container create --name vhd \
--account-name "${CLUSTER_NAME}"sa --account-key "${ACCOUNT_KEY}" \
--output table

#az storage blob upload --account-name ${CLUSTER_NAME}sa \
#--account-key ${ACCOUNT_KEY} -c vhd -n "rhcos-410.84.202201251210-0-azurestack.x86_64.vhd" \
#-f rhcos-*-azurestack.x86_64.vhd

#az storage blob upload --account-name opsmanagerimage \
#-c images -n "hcos-410.84.202201251210-0-azurestack.x86_64.vhd" \
#-f rhcos-*-azurestack.x86_64.vhd


###
az storage container create --name files \
--account-name "${CLUSTER_NAME}"sa --account-key "${ACCOUNT_KEY}" \
--public-access blob \
--output table
echo "Uploading Bootstrap Machine Config Files"

az storage blob upload --account-name "${CLUSTER_NAME}"sa \
--account-key "${ACCOUNT_KEY}" -c "files" \
-f "assets/bootstrap.ign" -n "bootstrap.ign" \
--output table
echo "Creating Network"
az deployment group create -g "${RESOURCE_GROUP}" \
--template-file "backup/01_vnet.json" --parameters baseName="${INFRA_ID}" \
--output table

export VHD_BLOB_URL=https://opsmanagerimage.blob.local.azurestack.external/images/rhcos-411.86.202207150124-0-azurestack.x86_64.vhd
# export VHD_BLOB_URL=`az storage blob url --account-name ${CLUSTER_NAME}sa \
#--account-key ${ACCOUNT_KEY} -c vhd -n "rhcos.vhd" -o tsv`
echo "Creating rhos Image"
az deployment group create -g "${RESOURCE_GROUP}" \
--template-file "backup/02_storage.json" \
--parameters vhdBlobURL="${VHD_BLOB_URL}" --parameters baseName="${INFRA_ID}" \
--output table
echo "Creating Infra"
az deployment group create -g "${RESOURCE_GROUP}" \
--template-file "backup/03_infra.json" --parameters baseName="${INFRA_ID}" \
--output table

PUBLIC_IP="$(az network public-ip list -g "${RESOURCE_GROUP}" \
--query "[?name=='${INFRA_ID}-master-pip'] | [0].ipAddress" -o tsv)"
export PUBLIC_IP
PRIVATE_IP="$(az network lb frontend-ip show -g "${RESOURCE_GROUP}" \
--lb-name "${INFRA_ID}-internal" -n internal-lb-ip --query "privateIpAddress" -o tsv)"
export PRIVATE_IP


az network dns zone create -g "${BASE_DOMAIN_RESOURCE_GROUP}" -n "${CLUSTER_NAME}"."${BASE_DOMAIN}"
az network dns record-set a add-record -g "${BASE_DOMAIN_RESOURCE_GROUP}" \
-z "${CLUSTER_NAME}"."${BASE_DOMAIN}" -n api -a "${PUBLIC_IP}" --ttl 60 \
--output table

az network dns record-set a add-record -g "${BASE_DOMAIN_RESOURCE_GROUP}" \
-z "${CLUSTER_NAME}.${BASE_DOMAIN}" -n api-int -a "${PRIVATE_IP}" --ttl 60 \
--output table

export BOOTSTRAP_URL="http://ocpcluster1sa.blob.local.azurestack.external/files/bootstrap.ign"

export CA="data:text/plain;charset=utf-8;base64,$(cat root.pem |base64 |tr -d '\n')"
# export BOOTSTRAP_URL=$(az storage blob url --account-name "${INFRA_ID}sa" --account-key "$ACCOUNT_KEY" -c "files" -n "bootstrap.ign" -o tsv)
export BOOTSTRAP_IGNITION=$(jq -rcnM --arg v "3.2.0" --arg url "$BOOTSTRAP_URL" --arg cert "$CA" '{ignition:{version:$v,security:{tls:{certificateAuthorities:[{source:$cert}]}},config:{replace:{source:$url}}}}' | base64 | tr -d '\n')


# BOOTSTRAP_IGNITION=$(jq -rcnM --arg v "3.2.0" \
#--arg url ${BOOTSTRAP_URL} \
#'{ignition:{version:$v,config:{replace:{source:$url}}}}' | base64 | tr -d '\n')
#export BOOTSTRAP_IGNITION
echo "Creating Bootstrap VM"
az deployment group create --verbose -g "${RESOURCE_GROUP}" \
--template-file "backup/04_bootstrap.json" \
--parameters bootstrapIgnition="${BOOTSTRAP_IGNITION}" \
--parameters sshKeyData="${SSH_KEY}" \
--parameters baseName="${INFRA_ID}" \
--parameters diagnosticsStorageAccountName="${CLUSTER_NAME}sa" \
--output table

echo "deploying Master Machines"
MASTER_IGNITION="$(base64 < ./assets/master.ign | tr -d '\n' )"
export MASTER_IGNITION
az deployment group create -g "${RESOURCE_GROUP}" \
--template-file "backup/05_masters.json" \
--parameters masterIgnition="${MASTER_IGNITION}" \
--parameters sshKeyData="${SSH_KEY}" \
--parameters baseName="${INFRA_ID}" \
--parameters diagnosticsStorageAccountName="${CLUSTER_NAME}sa" \
--output table 

openshift-install wait-for bootstrap-complete --dir=assets --log-level debug

openshift-install wait-for bootstrap-complete --dir=assets --log-level debug


az network nsg rule delete -g $RESOURCE_GROUP --nsg-name ${INFRA_ID}-nsg --name bootstrap_ssh_in
az vm stop -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap
az vm deallocate -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap
az vm delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap --yes
az disk delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap_OSDisk --no-wait --yes
az network nic delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap-nic --no-wait
az storage blob delete --account-key $ACCOUNT_KEY --account-name ${CLUSTER_NAME}sa --container-name files --name bootstrap.ign
az network public-ip delete -g $RESOURCE_GROUP --name ${INFRA_ID}-bootstrap-ssh-pip

export KUBECONFIG=$PWD/assets/auth/kubeconfig

export WORKER_IGNITION=$(cat $PWD/assets/worker.ign | base64 | tr -d '\n')


az deployment group create -g $RESOURCE_GROUP \
  --template-file "backup/06_workers.json" \
  --parameters workerIgnition="$WORKER_IGNITION" \
  --parameters sshKeyData="$SSH_KEY" \
  --parameters baseName="$INFRA_ID" \
  --parameters diagnosticsStorageAccountName="${INFRA_ID}sa"

watch oc get csr -A
oc patch cloudcredential cluster --type 'merge' -p '{"metadata": {"annotations": {"cloudcredential.openshift.io/upgradeable-to": "4.11.0"}}}'

export PPDM_K8S_TOKEN=$(oc get secret "$(oc -n kube-system get secret | grep ppdm-admin-token-w | awk '{print $1}')" \
-n kube-system --template={{.data.token}} | base64 -d)


oc cluster-info
oc get nodes



oc import-image -n openshift postgresql:12-el8
oc create ns jfrog
oc process -f https://raw.githubusercontent.com/openshift/library/master/official/postgresql/templates/postgresql-persistent.json \
  -p POSTGRESQL_VERSION=12-el8 \
  -p POSTGRESQL_USER=jfrog \
  -p POSTGRESQL_PASSWORD=jfrog \
  -p POSTGRESQL_DATABASE=jfrog  | oc apply -n jfrog -f -

oc label namespace jfrog ppdm_policy=PPDM_GOLD


oc apply -f https://raw.githubusercontent.com/bottkars/dps-modules/main/ci/templates/ppdm/ppdm-rbac.yml
oc apply -f https://raw.githubusercontent.com/bottkars/dps-modules/main/ci/templates/ppdm/ppdm-admin.yml
export PPDM_K8S_TOKEN=$(oc get secret "$(oc -n kube-system get secret | grep ppdm-admin-token | head -n1 | awk '{print $1}')" \
-n kube-system --template={{.data.token}} | base64 -d)



KEY=$(openssl rand -hex 32)
TARGET_NAMESPACE=artifactory-demo

oc new-project ${TARGET_NAMESPACE}

NAMESPACE_UID=$(oc get namespace/${TARGET_NAMESPACE} -o jsonpath="{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}" | cut -f1 -d'/')
NAMESPACE_GID=$(oc get namespace/${TARGET_NAMESPACE} -o jsonpath="{.metadata.annotations.openshift\.io/sa\.scc\.supplemental-groups}" | cut -f1 -d'/')

oc delete-f - <<EOF
apiVersion: charts.helm.k8s.io/v1
kind: OpenshiftArtifactoryHa
metadata:
  name: openshiftartifactoryha
  namespace: openshift-operators  
spec:
  artifactory-ha:
    artifactory:
      joinKey: ${KEY}
      masterKey: ${KEY}
      uid: ${NAMESPACE_UID}
      node:
        replicaCount: 2
        waitForPrimaryStartup:
          enabled: false
    databaseUpgradeReady: true
    database:
      driver: org.postgresql.Driver
      password: jfrog
      type: postgresql
      url: jdbc:postgresql://postgresql:5432/jfrog
      user: jfrog
    nginx:
      uid: ${NAMESPACE_UID}
      gid: ${NAMESPACE_GID}
      http:
        externalPort: 80
        internalPort: 8080
      https:
        externalPort: 443
        internalPort: 8443
      service:
        ssloffload: false
      tlsSecretName: jfrog-cert
    postgresql:
      enabled: false
    waitForDatabase: true
EOF


