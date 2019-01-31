#!/usr/bin/env bash

set -Eeuxo pipefail

readonly REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"

enable_lio() {
    echo "Enable LIO"
    # Disable update temporarily. Ubuntu package repo seems to be failing with
    # error: Some index files failed to download.
    # sudo apt -y update
    sudo apt -y install linux-image-extra-$(uname -r)
    sudo mount --make-shared /sys
    sudo mount --make-shared /
    sudo mount --make-shared /dev
    docker run --name enable_lio --privileged --rm --cap-add=SYS_ADMIN -v /lib/modules:/lib/modules -v /sys:/sys:rshared storageos/init:0.1
    echo
}

run_kind() {
    echo "Download kind binary..."
    # docker run --rm -it -v "$(pwd)":/go/bin golang go get sigs.k8s.io/kind && sudo mv kind /usr/local/bin/
    wget -O kind 'https://docs.google.com/uc?export=download&id=1C_Jrj68Y685N5KcOqDQtfjeAZNW2UvNB' --no-check-certificate && chmod +x kind && sudo mv kind /usr/local/bin/

    echo "Download kubectl..."
    curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/"${K8S_VERSION}"/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
    echo

    echo "Create Kubernetes cluster with kind..."
    # kind create cluster --image=kindest/node:"$K8S_VERSION"
    kind create cluster --image storageos/kind-node:"$K8S_VERSION" --config test/kind-config.yaml

    echo "Export kubeconfig..."
    # shellcheck disable=SC2155
    export KUBECONFIG="$(kind get kubeconfig-path)"
    echo

    echo "Get cluster info..."
    kubectl cluster-info
    echo

    echo "apply pod security policy for the pods in kube-system namespace"
    kubectl apply -f test/privileged-psp-with-rbac.yaml
    echo

    echo "Wait for kubernetes to be ready"
    JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'; until kubectl get nodes -o jsonpath="$JSONPATH" 2>&1 | grep -q "Ready=True"; do sleep 1; done
    echo
}

run_minikube() {
    echo "Install socat and util-linux"
    sudo apt-get install -y socat util-linux
    echo

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
    sudo -E minikube start --vm-driver=none --cpus 2 --memory 4096 --bootstrapper=localkube --kubernetes-version=${K8S_VERSION} --extra-config=apiserver.Authorization.Mode=RBAC

    echo "Enable add-ons..."
    sudo minikube addons disable kube-dns
    sudo minikube addons enable coredns
    echo

    # Fix the kubectl context, as it's often stale.
    # - minikube update-context
    # Wait for Kubernetes to be up and ready.
    JSONPATH='{range .items[*]}{@.metadata.name}:{range @.status.conditions[*]}{@.type}={@.status};{end}{end}'; until kubectl get nodes -o jsonpath="$JSONPATH" 2>&1 | grep -q "Ready=True"; do sleep 1; done
    echo

    echo "Get cluster info..."
    kubectl cluster-info
    echo

    echo "Create cluster admin..."
    kubectl create clusterrolebinding add-on-cluster-admin --clusterrole=cluster-admin --serviceaccount=kube-system:default
    echo
}

run_tillerless() {
     # -- Work around for Tillerless Helm, till Helm v3 gets released -- #
     docker exec "$config_container_id" apk add bash
     echo "Install Tillerless Helm plugin..."
     docker exec "$config_container_id" helm init --client-only
     docker exec "$config_container_id" helm plugin install https://github.com/rimusz/helm-tiller
     docker exec "$config_container_id" bash -c 'echo "Starting Tiller..."; helm tiller start-ci >/dev/null 2>&1 &'
     docker exec "$config_container_id" bash -c 'echo "Waiting Tiller to launch on 44134..."; while ! nc -z localhost 44134; do sleep 1; done; echo "Tiller launched..."'
     echo
}

install_tiller() {
    # Install Tiller with RBAC
    kubectl -n kube-system create sa tiller
    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    docker exec "$config_container_id" helm init --service-account tiller
    echo "Wait for Tiller to be up and ready..."
    until kubectl -n kube-system get pods 2>&1 | grep -w "tiller-deploy"  | grep -w "1/1"; do sleep 1; done
    echo
}

main() {
    enable_lio
    run_kind

    echo "Ready for testing"

    local config_container_id
    config_container_id=$(docker run -it -d -v "$REPO_ROOT:/workdir" --workdir /workdir "$CHART_TESTING_IMAGE:$CHART_TESTING_TAG" cat)

    # shellcheck disable=SC2064
    trap "docker rm -f $config_container_id > /dev/null" EXIT

    # Get kind container IP
    kind_container_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kind-1-control-plane)
    # Copy kubeconfig file
    docker exec "$config_container_id" mkdir /root/.kube
    docker cp "$KUBECONFIG" "$config_container_id:/root/.kube/config"
    # Update in kubeconfig from localhost to kind container IP
    docker exec "$config_container_id" sed -i "s/localhost:.*/$kind_container_ip:6443/g" /root/.kube/config

    echo "Add git remote k8s ${CHARTS_REPO}"
    git remote add storageos "${CHARTS_REPO}" &> /dev/null || true
    git fetch storageos master
    echo

    install_tiller

    # shellcheck disable=SC2086
    docker exec "$config_container_id" ct install --debug --config /workdir/test/ct.yaml
    # ------------------------------------------------------------------- #

    ##### docker exec "$config_container_id" ct install ${CHART_TESTING_ARGS} --config /workdir/test/ct.yaml

    echo "Done Testing!"
}

main
