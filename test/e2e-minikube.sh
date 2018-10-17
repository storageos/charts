#!/usr/bin/env bash

set -Eeuxo pipefail

enable_lio() {
    echo "Enable LIO"
    sudo apt -y update
    sudo apt -y install linux-image-extra-$(uname -r)
    sudo mount --make-rshared /sys
    docker run --name enable_lio --privileged --rm --cap-add=SYS_ADMIN -v /lib/modules:/lib/modules -v /sys:/sys:rshared storageos/init:0.1
    echo
}

run_minikube() {
    echo "Copy nsenter tool for Ubuntu 14.04 (current travisCI build VM version)"
    # shellcheck disable=SC2046
    sudo docker run --rm -v $(pwd):/target jpetazzo/nsenter
    sudo mv -fv nsenter /usr/local/bin/
    echo

    echo "Run minikube"
    # Download kubectl, which is a requirement for using minikube.
    curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
    # Download minikube.
    curl -Lo minikube https://github.com/kubernetes/minikube/releases/download/${MINIKUBE_VERSION}/minikube-linux-amd64 && chmod +x minikube && sudo mv minikube /usr/local/bin/
    # TODO: remove the --bootstrapper flag once this issue is solved: https://github.com/kubernetes/minikube/issues/2704
    sudo minikube config set WantReportErrorPrompt false
    sudo -E minikube start --vm-driver=none --cpus 2 --memory 2048 --bootstrapper=localkube --kubernetes-version=${K8S_VERSION} --extra-config=apiserver.Authorization.Mode=RBAC
    # Fix the kubectl context, as it's often stale.
    # - minikube update-context
    # Wait for Kubernetes to be up and ready.
    JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'; until kubectl get nodes -o jsonpath="$JSONPATH" 2>&1 | grep -q "Ready=True"; do sleep 1; done
    echo
}

install_helm() {
    # socat is required for helm client-tiller communication.
    echo "Install socat and util-linux"
    sudo apt-get update
    sudo apt-get install -y socat util-linux
    echo

    echo "Install helm"
    curl https://raw.githubusercontent.com/helm/helm/master/scripts/get | bash
    kubectl -n kube-system create sa tiller
    kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
    helm init --wait --service-account tiller
    echo
}

main() {
    enable_lio
    run_minikube
    install_helm

    echo "Ready for testing"
}

main
