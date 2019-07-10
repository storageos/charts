#!/bin/bash
set -e

# This script is used to publish storageos-operator chart to the upstream
# rancher charts repo. It creates a diff of 

# Chart version.
VERSION=$(yq r stable/storageos-operator/Chart.yaml version)

docker run --rm -ti \
    -v $PWD:/go/src/github.com/storageos/charts \
    -e GITHUB_USER=$GH_USER \
    -e GITHUB_EMAIL=$GH_EMAIL \
    -e GITHUB_TOKEN=$API_TOKEN \
    -e VERSION=$VERSION \
    -e TARGET_REPO="https://github.com/rancher/charts/" \
    -e FORK_REPO=$FORK_REPO \
    -e UPSTREAM_REPO_PATH="/go/src/github.com/rancher/charts" \
    -e UPSTREAM_CHART_PATH="proposed/" \
    -e CHART_ROOT=stable/storageos-operator/ \
    -w /go/src/github.com/storageos/charts \
    tianon/github-hub:2 bash -c "./scripts/create-pr.sh"
