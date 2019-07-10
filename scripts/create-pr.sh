#!/bin/bash
set -e

# This script uses github hub https://hub.github.com/ to create a pull request.

# Env vars definitions:-
# 
# GITHUB_USER: github username
# GITHUB_EMAIL: github user email
# GITHUB_TOKEN: github user API token with repo access permission only
# VERSION: chart version
# TARGET_REPO: upstream charts repo
# UPSTREAM_REPO_PATH: upstream charts repo path
# UPSTREAM_CHART_PATH: target charts dir path in the upstream charts repo
# CHART_ROOT: path to the directory containing the chart.


# Setup netrc.
echo "machine github.com
  login $GITHUB_USER
  password $GITHUB_TOKEN
" > ~/.netrc

# Configure git.
git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$GITHUB_USER"

# Clone rancher charts repo.
git clone $TARGET_REPO $UPSTREAM_REPO_PATH

# Copy storageos chart changes.
cp -r $CHART_ROOT $UPSTREAM_REPO_PATH/$UPSTREAM_CHART_PATH

# Create branch, commit and create a PR.
MESSAGE="Update storageos-operator to version ${VERSION}"
echo $MESSAGE
pushd $UPSTREAM_REPO_PATH
if ! git diff-index --quiet HEAD --; then
    echo "Found changes in storageos-operator chart"
    echo "Creating pull request to the rancher chart.."
    git status
    hub remote add fork $FORK_REPO
    git checkout -b $VERSION
    git add *
    git status
    git commit -m "$MESSAGE"
    git push fork $VERSION
    hub pull-request -m "$MESSAGE"
else
    echo "storageos-operator chart is in sync with rancher charts. Do nothing."
fi
