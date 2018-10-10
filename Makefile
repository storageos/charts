
setup:
	mkdir packages

package:
	helm package stable/* -d packages/

index:
	helm repo index packages/ --url https://storage.googleapis.com/storageos-charts-testing

deploy:
	gsutil cp packages/* gs://storageos-charts-testing

all: setup package index deploy
