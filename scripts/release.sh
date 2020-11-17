#!/bin/bash
set -e

# This script is used to publish storageos-operator chart to the upstream
# rancher charts repo. It creates a new base copy for the new version using
# the latest release and copies the new changes to the new base copy. It then
# creates a pull request with all the changes to the upstream rancher charts
# repo.

# Chart version.
VERSION=$(yq r stable/storageos-operator/Chart.yaml version)

docker run --rm -ti \
    -v $PWD:/go/src/github.com/storageos/charts \
    -e GITHUB_USER=$GH_USER \
    -e GITHUB_EMAIL=$GH_EMAIL \
    -e SIGN_OFF_NAME=$SIGN_OFF_NAME \
    -e GITHUB_TOKEN=$API_TOKEN \
    -e VERSION=$VERSION \
    -e TARGET_REPO="https://github.com/rancher/charts/" \
    -e TARGET_BRANCH="master" \
    -e FORK_REPO=$FORK_REPO \
    -e UPSTREAM_REPO_PATH="/go/src/github.com/rancher/charts" \
    -e UPSTREAM_CHART_PATH="charts" \
    -e CHART_NAME=$CHART_NAME \
    -e CHART_ROOT=stable/storageos-operator \
    -w /go/src/github.com/storageos/charts \
    tianon/github-hub:2 bash -c "./scripts/create-pr.sh"
