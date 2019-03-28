# StorageOS Operator Helm Chart

> **Note**: This is the recommended chart to use for installing StorageOS.
installs the StorageOS Operator, and then installs StorageOS as a DaemonSet.
Other Helm charts ([storageoscluster-operator](https://github.com/storageos/charts/tree/master/stable/storageoscluster-operator) and [storageos](https://github.com/storageos/charts/tree/master/stable/storageos))
will be deprecated.

[StorageOS](https://storageos.com) is a software-based storage platform
designed for cloud-native applications. By deploying StorageOS on your
Kubernetes cluster, local storage from cluster node is aggregated into a
distributed pool, and persistent volumes created from it using the native
Kubernetes volume driver are available instantly to pods wherever they move in
the cluster.

Features such as replication, encryption and caching help protect data and
maximise performance.

This chart installs a StorageOS Cluster Operator which helps deploy and
configure a StorageOS cluster on kubernetes.

## Prerequisites

- Kubernetes 1.9+.
- Privileged mode containers (enabled by default)
- Kubernetes 1.9 only:
  - Feature gate: MountPropagation=true.  This can be done by appending
    `--feature-gates MountPropagation=true` to the kube-apiserver and kubelet
    services.

Refer to the [StorageOS prerequisites
docs](https://docs.storageos.com/docs/prerequisites/overview) for more
information.

## Installing the chart

```console
# Add storageos charts repo.
$ helm repo add storageos https://charts.storageos.com
# Install the chart in a namespace.
$ helm install storageos/storageos-operator --namespace storageos-operator
```

This will install the StorageOSCluster operator in `storageos-operator`
namespace.

> **Tip**: List all releases using `helm list`

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
  apiAddress: c3RvcmFnZW9zOjU3MDU=
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

Once the `StorageOSCluster` configuration is applied, the StorageOSCluster
operator would setup a storageos cluster in the `storageos` namespace by
default.

Most installations will want to use the default [CSI](https://kubernetes-csi.github.io/docs/)
driver.  To use the [Native Driver](https://kubernetes.io/docs/concepts/storage/volumes/#storageos)
instead, disable CSI:

```yaml
spec:
  ...
  csi:
    enable: false
  ...
```

in the above `StorageOSCluster` resource config.

To check cluster status, run:

```bash
$ kubectl get storageoscluster
NAME                READY     STATUS    AGE
example-storageos   3/3       Running   4m
```

All the events related to this cluster are logged as part of the cluster object
and can be viewed by describing the object.

```bash
$ kubectl describe storageoscluster example-storageos
Name:         example-storageos
Namespace:    default
Labels:       <none>
...
...
Events:
  Type     Reason         Age              From                       Message
  ----     ------         ----             ----                       -------
  Warning  ChangedStatus  1m (x2 over 1m)  storageos-operator  0/3 StorageOS nodes are functional
  Normal   ChangedStatus  35s              storageos-operator  3/3 StorageOS nodes are functional. Cluster healthy
```

### Setup Automatic Cleanup

The above setup would create storageos data at `/var/lib/storageos`. In order to
setup automatic cleanup when a cluster is deleted, the chart's `cleanup.enable`
must be set to `true` in `values.yaml` before install the chart. This would
install some extra components for automatic cleanup of storageos cluster data.
In addition to that, the StorageOS cluster spec must also have `cleanupAtDelete`
set to `true`. With this set, when a cluster is deleted, the data and
configurations associated with the cluster are also deleted.

## Configuration

The following tables lists the configurable parameters of the StorageOSCluster
Operator chart and their default values.

Parameter | Description | Default
--------- | ----------- | -------
`image.repository` | StorageOSCluster container image repository | `storageos/cluster-operator`
`image.tag` | StorageOSCluster container image tag | `1.1.0`
`image.pullPolicy` | StorageOSCluster container image pull policy | `IfNotPresent`

## Deleting a StorageOS Cluster

Deleting the `StorageOSCluster` custom resource object would delete the
storageos cluster and all the associated resources.

In the above example,

```bash
kubectl delete storageoscluster example-storageos
```

would delete the custom resource and the cluster.

## Uninstalling the Chart

To uninstall/delete the storageos cluster operator deployment:

```bash
helm delete --purge <release-name>
```

Learn more about configuring the StorageOS Operator on
[GitHub](https://github.com/storageos/cluster-operator).
