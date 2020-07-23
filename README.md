# StorageOS Helm Charts

[![Build Status](https://travis-ci.org/storageos/charts.svg?branch=helm2)](https://travis-ci.org/storageos/charts)
[![CircleCI](https://circleci.com/gh/storageos/charts/tree/helm2.svg?style=svg)](https://circleci.com/gh/storageos/charts/tree/helm2)


This repository hosts the official StorageOS Helm Charts.

**NOTE**: This branch is for supporting rancher charts with helm2. For helm3
chart, use the chart in the main branch.

## Install

Get the latest [Helm release](https://github.com/helm/helm#install).

## Install Charts

Add the StorageOS chart repo to Helm:

```bash
helm repo add storageos https://charts.storageos.com
helm repo update
```

Run `helm search storageos` to list the available charts.
