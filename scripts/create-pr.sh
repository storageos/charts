#!/bin/bash
set -e

# This script uses github hub https://hub.github.com/ to create a pull request
# and create a new rancher charts release.

# Env vars definitions:-
# 
# GITHUB_USER: github username
# GITHUB_EMAIL: github user email
# GITHUB_TOKEN: github user API token with repo access permission only
# SIGN_OFF_NAME: git commit sign-off name
# VERSION: chart version
# TARGET_REPO: upstream charts repo
# TARGET_BRANCH: upstream repo branch
# UPSTREAM_REPO_PATH: upstream charts repo path
# UPSTREAM_CHART_PATH: target charts dir path in the upstream charts repo
# CHART_ROOT: path to the directory containing the chart.
# CHART_NAME: name of the rancher chart


# Setup netrc.
echo "machine github.com
  login $GITHUB_USER
  password $GITHUB_TOKEN
" > ~/.netrc

# Configure git.
git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$SIGN_OFF_NAME"


# Clone rancher charts repo.
git clone $TARGET_REPO $UPSTREAM_REPO_PATH

# Change branch to target branch.
pushd $UPSTREAM_REPO_PATH
# Checkout to the target branch if it's not master.
if [ "$TARGET_BRANCH" != "master" ]; then
    git checkout --track origin/$TARGET_BRANCH
fi
popd

# Get the latest release and new version.
latest=$(ls $UPSTREAM_REPO_PATH/$UPSTREAM_CHART_PATH/$CHART_NAME | sort -nr | head -n1)
new_version=v$VERSION

# Compare latest rancher chart version with original chart version and exit if
# the versions are the same.
if [ "$latest" == "$new_version" ]; then
    echo "No new rancher chart to publish"
    exit 0
else
    echo "Preparing to publishing new chart version ${new_version}"
fi

echo "Using $latest to create base copy of $new_version"

# Create a base copy by copying previous version to new version directory.
latest_path=$UPSTREAM_REPO_PATH/$UPSTREAM_CHART_PATH/$CHART_NAME/$latest
new_path=$UPSTREAM_REPO_PATH/$UPSTREAM_CHART_PATH/$CHART_NAME/$new_version
cp -r $latest_path $new_path

# Commit base copy.
BASE_COPY_MSG="${CHART_NAME}: base copy ${latest} to ${new_version}"
echo "Commit: ${BASE_COPY_MSG}"
pushd $UPSTREAM_REPO_PATH
# Create a new branch from the target branch(being explicit).
git checkout -b $new_version $TARGET_BRANCH
git add *
git status
# Sign-off the commit.
git commit -m "$BASE_COPY_MSG" -s
popd

# Copy new chart changes.
cp -r $CHART_ROOT/* $new_path

# Create branch, commit and create a PR.
MESSAGE="Update ${CHART_NAME} to version ${VERSION}"
echo "Commit: ${MESSAGE}"
pushd $UPSTREAM_REPO_PATH
if ! git diff-index --quiet HEAD --; then
    echo "Found changes in ${CHART_NAME} chart"
    echo "Creating pull request to the rancher chart.."
    git status
    hub remote add fork $FORK_REPO
    git add *
    git status
    # Sign-off the commit.
    git commit -m "$MESSAGE" -s
    git push fork $new_version
    hub pull-request -m "$MESSAGE"
else
    echo "${CHART_NAME} chart is in sync with rancher charts. Do nothing."
fi
