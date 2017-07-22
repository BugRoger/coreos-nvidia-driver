COREOS_TRACK   ?= beta
COREOS_VERSION ?= 1409.1.0

.PHONY: all
all: version.txt coreos_developer_container.bin
	export $(cat version.txt | xargs)
	mkdir ${COREOS_VERSION}
	sudo mount -o ro,loop,offset=2097152 coreos_developer_container.bin ${COREOS_VERSION}
	sudo tar -cp --one-file-system -C ${COREOS_VERSION} . | docker import - bugroger/coreos-developer:${COREOS_VERSION}
	docker push bugroger/coreos-developer:${COREOS_VERSION}

version.txt:
	curl https://${COREOS_TRACK}.release.core-os.net/amd64-usr/current/version.txt -o version.txt

coreos_developer_container.bin: coreos_developer_container.bin.bz2
	bunzip2 -k coreos_developer_container.bin.bz2

coreos_developer_container.bin.bz2:
	curl -L https://${COREOS_TRACK}.release.core-os.net/amd64-usr/${COREOS_VERSION}/coreos_developer_container.bin.bz2 -o coreos_developer_container.bin.bz2
