export CLUSTER_NAME="seqr-es-cluster-prod2"
export CONTEXT_NAME="gke_mcri-01_australia-southeast1-b_seqr-es-cluster-prod2"
export ENV=prod
export GCP_ZONE="australia-southeast1-b"
export GCP_PROJECT="mcri-01"
# New pool details
export NEW_POOL_NAME="prod2-highmem4-pool"
export NEW_MACHINE_TYPE="e2-highmem-4"
export NEW_POOL_NUM_NODES=5
export NEW_POOL_MIN_NODES=5
export NEW_POOL_MAX_NODES=6
export NEW_POOL_DISK_SIZE=100
export NEW_ELASTICSEARCH_CONFIG="elasticsearch.highmem4.yaml"
# Existing pool details
export OLD_POOL_NAME="default-pool"

# Ensure that you switch to the correct cluster and context
kubectl config use-context $CONTEXT_NAME
gcloud container clusters get-credentials $CLUSTER_NAME --zone $GCP_ZONE --project $GCP_PROJECT

# Step 1. Create a new node-pool with the new machine type
gcloud container node-pools create $NEW_POOL_NAME \
  --cluster $CLUSTER_NAME \
  --zone $GCP_ZONE \
  --machine-type $NEW_MACHINE_TYPE \
  --num-nodes $NEW_POOL_NUM_NODES \
  --enable-autoscaling --min-nodes $NEW_POOL_MIN_NODES --max-nodes $NEW_POOL_MAX_NODES \
  --disk-type pd-standard \
  --disk-size $NEW_POOL_DISK_SIZE \
  --image-type COS_CONTAINERD \
  --node-labels env=$ENV,nodeType=default \
  --metadata disable-legacy-endpoints=true \
  --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
  --enable-autoupgrade \
  --enable-autorepair \
  --tags "default"

# Step 2. Cordon and Drain Nodes
for node_name in $(kubectl get nodes -l cloud.google.com/gke-nodepool=$OLD_POOL_NAME -o custom-columns=NAME:.metadata.name --no-headers);
do
  kubectl cordon $node_name;
  kubectl drain $node_name --ignore-daemonsets --delete-emptydir-data;
done

# Step 3. Apply the new elasticsearch yaml config
kubectl apply -f $NEW_ELASTICSEARCH_CONFIG;

# Step 4. Delete the old pool: Note until this is done -- nodes will keep appearing even though we've drained them
gcloud container node-pools delete $OLD_POOL_NAME \
  --cluster $CLUSTER_NAME  \
  --zone $GCP_ZONE \
  --project $GCP_PROJECT

# Step 5. Checks
# Ensure that pods are not PENDING or FAILED:
# kubectl get pods -o wide

# If need be you can run:
# kubectl describe pod [PODNAME]
# e.g. kubectl describe pod elasticsearch-es-data-2
# This will give you details regarding why things have failed

# Step 6. If necessary
# Change autoscaling min and max nodees
# gcloud container clusters update $CLUSTER_NAME \
#   --node-pool $POOL_NAME \
#   --min-nodes=FIXME_NEW_VALUE_A \
#   --max-nodes=FIXME_NEW_VALUE_B \
#   --zone $GCP_ZONE \
#   --project $GCP_PROJECT
