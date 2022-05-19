# MCRI Elasticsearch Deployment (**DEPRECATED**)

**THIS DOCUMENT IS DEPRECATED** - See [README](../elasticsearch/README.md) for latest version.

This directory contains instructions and all deployment descriptors required
for deploying Seqr's Elasticsearch instance at MCRI, hosted on Google Kubernetes Engine.

This is based originally from [ssadedin/kubernetes-elasticsearch-cluster](https://github.com/ssadedin/kubernetes-elasticsearch-cluster)
which is a fork from [pires/kubernetes-elasticsearch-cluster](https://github.com/pires/kubernetes-elasticsearch-cluster).

The K8 deployment descriptions still depend on the Docker containers originally build by pires, hosted on `quay.io/pires`.

## Prerequisites

* [Google Cloud SDK](https://cloud.google.com/sdk/install) installed.
* [Google Cloud SDK](https://cloud.google.com/sdk/docs/authorizing) initialized and authorized.
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) installed, this is the Kubernetes command-line tool.

## Creating New GKE Cluster

Use gcloud to create a new cluster.  This cluster is created with Gce CSI Driver, see [Using the Compute Engine persistent disk CSI Driver](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/gce-pd-csi-driver).

```bash
export CLUSTER_NAME=seqr-cluster-prod-a

gcloud beta container clusters create $CLUSTER_NAME \
  --zone=australia-southeast1-b \
  --num-nodes=1 \
  --cluster-version=1.16 \
  --machine-type=n1-highmem-4 \
  --enable-ip-alias \
  --addons=GcePersistentDiskCsiDriver
```

Above command should have also configured `kubectl` with authentication and use this new cluster as its default context.
If the cluster already exists, run this command to have `kubectl` authenticate with this cluster.

```bash
gcloud container clusters get-credentials $CLUSTER_NAME
```

or if your authentication is already configured with the cluster then simply get `kubectl` to
change context to this new cluster.

```bash
kubectl config use-context $CLUSTER_NAME
```

## Configuring New GKE Cluster

### Applying Kubernetes Elasticsearch Components

Before applying below K8 deployment descriptors, please ensure required persistent disks
already exists.  See [Using preexisting persistent disks as PersistentVolumes](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/preexisting-pd)
and [Adding or resizing zonal persistent disks](https://cloud.google.com/compute/docs/disks/add-persistent-disk).

The required persistent disks can be found in `es-pvs.yaml` and the names of these persistent disks must match the name in `pdName` properties.

For Minikube, use `ev-pvs-mk.yaml`.

```bash
cd $SEQR/mcri_deploy/kubernetes/elasticsearch-sharded

kubectl apply -f ../standard-expandable-storage-class.yaml

# For GKE
kubectl apply -f es-pvs.yaml

# For local minikube, apply es-pvs-mk.yaml instead of ev-pvs.yaml
# kubectl apply -f es-pvs-mk.yaml

kubectl apply -f es-discovery-svc.yaml
kubectl apply -f es-svc.yaml

kubectl apply -f es-master-svc.yaml
kubectl apply -f es-master-stateful.yaml
kubectl rollout status -f es-master-stateful.yaml

kubectl apply -f es-ingest-svc.yaml
kubectl apply -f es-ingest.yaml
kubectl rollout status -f es-ingest.yaml

kubectl apply -f es-data-svc.yaml
kubectl apply -f es-data-stateful.yaml
kubectl rollout status -f es-data-stateful.yaml
```

## StatefulSets Volume Expansion Not Yet Supported

In theory, this configuration should allow dynamic volume expansions.  However, this is not
yet supported for StatefulSets.  This means if you try to reapply StatefulSet changes with
new storage request size you'll get an error:

```bash
kubectl apply -f es-data-stateful.yaml
The StatefulSet "es-data" is invalid: spec: Forbidden: updates to statefulset spec for fields other than 'replicas', 'template', and 'updateStrategy' are forbidden
```

Below links provide more information.

* [Elasticsearch Nodes orchestration limitations](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-orchestration.html#k8s-orchestration-limitations)
* [Support Volume Expansion Through StatefulSets](https://github.com/kubernetes/enhancements/issues/661)
