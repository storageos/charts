#!/usr/bin/env bash

set -Eeuxo pipefail

readonly REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
readonly CLUSTER_NAME="kind-1"

enable_lio() {
    echo "Enable LIO"
    # Disable update temporarily. Ubuntu package repo seems to be failing with
    # error: Some index files failed to download.
    # sudo apt -y update
    sudo apt -y install linux-modules-extra-$(uname -r)
    sudo mount --make-shared /sys
    sudo mount --make-shared /
    sudo mount --make-shared /dev
    docker run --name enable_lio --privileged --rm --cap-add=SYS_ADMIN -v /lib/modules:/lib/modules -v /sys:/sys:rshared storageos/init:0.1
    echo
}

run_kind() {
    echo "Download kind binary..."
    # docker run --rm -it -v "$(pwd)":/go/bin golang go get sigs.k8s.io/kind && sudo mv kind /usr/local/bin/
    wget -O kind 'https://github.com/kubernetes-sigs/kind/releases/download/v0.6.0/kind-linux-amd64' --no-check-certificate && chmod +x kind && sudo mv kind /usr/local/bin/

    echo "Download kubectl..."
    curl -Lo kubectl https://storage.googleapis.com/kubernetes-release/release/"${K8S_VERSION}"/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
    echo

    echo "Create Kubernetes cluster with kind..."
    # kind create cluster --image=kindest/node:"$K8S_VERSION"
    kind create cluster --image storageos/kind-node:"$K8S_VERSION" --config test/kind-config.yaml --name "${CLUSTER_NAME}"

    echo "Set kubectl config context..."
    kubectl config use-context kind-"${CLUSTER_NAME}"
    # KUBECONFIG needs to be copied into KinD container later.
    export KUBECONFIG="${HOME}/.kube/config"
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

install_tiller() {
    # Install Tiller with RBAC
    kubectl -n kube-system create sa tiller
    kubectl create clusterrolebinding tiller-cluster-rule --clusterrole=cluster-admin --serviceaccount=kube-system:tiller
    docker_exec helm init --service-account tiller
    echo "Wait for Tiller to be up and ready..."
    until kubectl -n kube-system get pods 2>&1 | grep -w "tiller-deploy"  | grep -w "1/1"; do sleep 1; done
    echo
}

# Run commands inside charts-testing container.
docker_exec() {
    docker exec --interactive ct "$@"
}

# Run charts-testing container.
run_ct_container() {
    echo 'Running ct container...'
    docker run --rm --interactive --detach --network host --name ct \
        --volume "$REPO_ROOT:/workdir" \
        --workdir /workdir \
        "$CHART_TESTING_IMAGE:$CHART_TESTING_TAG" \
        cat
    echo
}

# Cleanup charts-testing container.
cleanup() {
    echo 'Removing ct container...'
    docker kill ct > /dev/null 2>&1

    echo 'Done!'
}

# Cleanup charts-testing and kind.
cleanup_kind() {
    cleanup
    echo 'Removing kind container...'
    kind delete cluster --name "${CLUSTER_NAME}" > /dev/null 2>&1
    echo 'Done!'
}

# Install helm cli.
install_helm() {
    echo 'Installing helm...'
    curl -sSLo tmp/helm.tar.gz "https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz"
    tar xf tmp/helm.tar.gz -C tmp
    sudo mv tmp/linux-amd64/helm /usr/local/bin
}

# Install kubeval.
install_kubeval() {
    echo 'Installing kubeval...'
    curl -sSLo tmp/kubeval.tar.gz "https://github.com/instrumenta/kubeval/releases/download/$KUBEVAL_VERSION/kubeval-linux-amd64.tar.gz"
    tar xf tmp/kubeval.tar.gz -C tmp && chmod +x tmp/kubeval
    sudo mv tmp/kubeval /usr/local/bin/kubeval
}

# Get a list of charts that changed.
get_changed_charts() {
    local changed_charts=("")
    while IFS='' read -r line; do changed_charts+=("$line"); done < <(docker run --rm -v "$(pwd):/workdir" --workdir /workdir "${CHART_TESTING_IMAGE}:${CHART_TESTING_TAG}" ct list-changed --chart-dirs stable )
    echo "${changed_charts[*]}"
}

# Render helm chart templates and validate the manifests.
validate_manifests() {
    kubeval_flags="--strict --ignore-missing-schemas --skip-kinds CustomResourceDefinition"
    local changed_charts=("")
    while IFS='' read -r line; do changed_charts+=("$line"); done < <(get_changed_charts)
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo " Validating Manifests!"
    echo " Charts to be processed: ${changed_charts[*]}"
    echo "------------------------------------------------------------------------------------------------------------------------"
    pushd tmp
    # Validate all the changed charts.
    for chart_name in ${changed_charts[*]} ; do
        echo "Validating chart ${chart_name}"
        rm -rf stable
        mkdir stable
        # Render chart with default values and validate.
        helm template "${REPO_ROOT}/${chart_name}" --output-dir stable > /dev/null 2>&1
        TEMPLATE_FILES="${chart_name}/templates"
        if [ -d "${TEMPLATE_FILES}" ]
        then
            echo "------------------------------------------------------------------------------------------------------------------------"
            echo "==> Processing with default values..."
            echo "------------------------------------------------------------------------------------------------------------------------"
            kubeval ${kubeval_flags} -d ${TEMPLATE_FILES}
            # If the chart contains ci/ dir, render the manifests with the
            # values in ci/ dir and validate again.
            if [ -d "${REPO_ROOT}/${chart_name}/ci" ]
            then
                FILES="${REPO_ROOT}/${chart_name}/ci/*"
                for file in $FILES
                do
                    echo "------------------------------------------------------------------------------------------------------------------------"
                    echo "==> Processing with $file..."
                    echo "------------------------------------------------------------------------------------------------------------------------"
                    rm -rf stable
                    mkdir stable
                    helm template "${REPO_ROOT}/${chart_name}" -f "$file" --output-dir stable > /dev/null 2>&1
                    TEMPLATE_FILES="${chart_name}/templates/*"
                    kubeval ${kubeval_flags} ${TEMPLATE_FILES}
                done
            fi
        fi
    done
    popd
    echo "------------------------------------------------------------------------------------------------------------------------"
    echo "Done Manifests validating!"
    echo
}

main() {
    # Download all the binaries and write all the rendered charts in tmp/.
    mkdir -p tmp

    # Install helm cli. This is required to render chart manifests and perform
    # kubeval validation check.
    install_helm
    install_kubeval

    echo "Add git remote k8s ${CHARTS_REPO}"
    git remote add storageos "${CHARTS_REPO}" &> /dev/null || true
    git fetch storageos master
    echo

    # Validate manifests with kubeval.
    validate_manifests

    # Setup e2e test.
    enable_lio
    run_ct_container

    # Cleanup at exit.
    trap cleanup_kind EXIT

    run_kind

    # Copy kubeconfig file
    echo "Copying kubeconfig into KinD container..."
    docker_exec mkdir -p /root/.kube
    docker cp "$KUBECONFIG" ct:/root/.kube/config

    docker_exec kubectl cluster-info
    echo

    # Install_tiller
    install_tiller

    echo "Ready for testing"

    docker_exec ct install --config /workdir/test/ct.yaml

    echo "Done Testing!"
}

main
