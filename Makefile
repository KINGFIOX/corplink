.PHONY: build push run

REPO := sleepymole/corplink
DATE := $(shell date +%Y%m%d)
SHA := $(shell git rev-parse --short HEAD)
DIRTY := $(shell git diff --quiet && git diff --cached --quiet || echo "-dirty")
TAG := v$(DATE)-$(SHA)${DIRTY}

all:
	docker build --platform=linux/amd64,linux/arm64 -t $(REPO):latest .
	docker tag $(REPO):latest $(REPO):$(TAG)

build:
	docker build -t $(REPO):latest .
	docker tag $(REPO):latest $(REPO):$(TAG)

push:
	docker push $(REPO):latest
	docker push $(REPO):$(TAG)

