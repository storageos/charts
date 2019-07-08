# StorageOSCluster Helm Chart

[StorageOS](https://storageos.com) is a software-based storage platform designed for cloud-native applications.  By
deploying StorageOS on your Kubernetes cluster, local storage from cluster node is aggregated into a distributed pool,
and persistent volumes created from it using the native Kubernetes volume driver are available instantly to pods
wherever they move in the cluster.

Features such as replication, encryption and caching help protect data and maximise performance.

This chart installs a StorageOS Cluster Operator which helps deploy and
configure a StorageOS cluster on kubernetes.

## Prerequisites

- Kubernetes 1.9+.
- Kubernetes must be configured to allow (configured by default in 1.10+):
    - Privileged mode containers (enabled by default)
    - Feature gate: MountPropagation=true.  This can be done by appending `--feature-gates MountPropagation=true` to the
      kube-apiserver and kubelet services.

Refer to the [StorageOS prerequisites docs](https://docs.storageos.com/docs/prerequisites/overview) for more information.


## Installing the chart

```console
# Add storageos charts repo.
$ helm repo add storageos https://charts.storageos.com
# Install the chart in a namespace.
$ helm install storageos/storageoscluster-operator --namespace storageos-operator
```

This will install the StorageOSCluster operator in `storageos-operator` namespace.

> **Tip**: List all releases using `helm list`

This chart installs some CRDs before installing the operator. Due to this, a
chart reinstall could fail due to existing CRD resources. Pass `--no-crd-hook`
flag to continue installing the chart without the CRDs.

```console
$ helm install storageos/storageoscluster-operator --namespace storageos-operator --no-crd-hook
```


## Creating a StorageOS cluster

Create a secret to store storageos cluster secrets:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: "storageos-api"
  namespace: "default"
  labels:
    app: "storageos"
type: "kubernetes.io/storageos"
data:
  # echo -n '<secret>' | base64
  apiUsername: c3RvcmFnZW9z
  apiPassword: c3RvcmFnZW9z
```

Create a `StorageOSCluster` custom resource and refer the above secret in
`secretRefName` and `secretRefNamespace` fields.

```yaml
apiVersion: "storageos.com/v1"
kind: "StorageOSCluster"
metadata:
  name: "example-storageos"
  namespace: "default"
spec:
  secretRefName: "storageos-api"
  secretRefNamespace: "default"
```

Once `StorageOSCluster` configuration is applied, the StorageOSCluster operator
would setup a storageos cluster in `storageos` namespace by default.

To enable StorageOS CSI setup, add:
```yaml
spec:
  ...
  csi:
    enable: true
  ...
```
in the above `StorageOSCluster` resource config.

To check cluster status, run:

```
$ kubectl get storageoscluster
NAME                READY     STATUS    AGE
example-storageos   3/3       Running   4m
```

All the events related to this cluster are logged as part of the cluster object
and can be viewed by describing the object.

```
$ kubectl describe storageoscluster example-storageos
Name:         example-storageos
Namespace:    default
Labels:       <none>
...
...
Events:
  Type     Reason         Age              From                       Message
  ----     ------         ----             ----                       -------
  Warning  ChangedStatus  1m (x2 over 1m)  storageoscluster-operator  0/3 StorageOS nodes are functional
  Normal   ChangedStatus  35s              storageoscluster-operator  3/3 StorageOS nodes are functional. Cluster healthy
```

## Configuration

The following tables lists the configurable parameters of the StorageOSCluster
Operator chart and their default values.

Parameter | Description | Default
--------- | ----------- | -------
`image.repository` | StorageOS Cluster Operator container image repository | `storageos/cluster-operator`
`image.tag` | StorageOS Cluster Operator container image tag | `1.3.0`
`image.pullPolicy` | StorageOS Cluster Operator container image pull policy | `IfNotPresent`
`podSecurityPolicy.enabled` | If true, create & use PodSecurityPolicy resources | `false`
`podSecurityPolicy.annotations` | Specify pod annotations in the pod security policy | `{}`


## Deleting a StorageOS Cluster

Deleting the `StorageOSCluster` custom resource object would delete the
storageos cluster and all the associated resources.

In the above example,
```
$ kubectl delete storageoscluster example-storageos
```

would delete the custom resource and the cluster.


## Uninstalling the Chart

To uninstall/delete the storageos cluster operator deployment:

```console
$ helm delete --purge <release-name>
```


Learn more about configuring `StorageOSCluster` at
[storageoscluster-operator](https://github.com/storageos/storageoscluster-operator).
