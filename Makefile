MAKEFLAGS+= --no-builtin-rules
MAKEFLAGS+= --no-builtin-variables
MAKEFLAGS+= --output-sync=line
MAKEFLAGS+= --no-print-directory

MAKE_JOBS?=$(shell nproc)

MAKEFLAGS+= --jobs=$(MAKE_JOBS)

ifneq ($(MAKE_JOBS),1)
MAKEFLAGS+= --output-sync=target
endif

BASH:=$(shell command -v bash)

ifndef BASH
$(error bash is unavailable, please install it)
endif

DOCKER:=$(shell command -v docker)

ifndef DOCKER
$(error docker is unavailable, please install it: https://docs.docker.com/engine/install/)
endif
#
GIT:=$(shell command -v git)

ifndef GIT
$(error git is unavailable, please install it: https://docs.docker.com/engine/install/)
endif

TAR:=$(shell command -v tar)

ifndef TAR
$(error tar is unavailable, please install it)
endif

define checkPermissions
$(shell if [ "0" != "$$(find $1 -type f ! -user $$(id -u) 2>/dev/null | wc -l)" ]; then echo "\`$1\` permissions are invalid, please execute \`sudo chown -R $$(id -u):$$(id -g) $1\` to fix them"; fi)
endef

FIX_NPM_CACHE_PERMISSIONS:=$(call checkPermissions,$(HOME)/.npm)

ifneq ($(FIX_NPM_CACHE_PERMISSIONS),)
$(error $(FIX_NPM_CACHE_PERMISSIONS))
endif

FIX_FILES_PERMISSIONS:=$(call checkPermissions,.)

ifneq ($(FIX_FILES_PERMISSIONS),)
$(error $(FIX_FILES_PERMISSIONS))
endif

-include .config.mk

DOCKER_REPOSITORY?=hub.docker.com
DOCKER_PROJECT?=file-manager
DOCKER_DEV_TAG?=$(shell $(GIT) branch --show-current | sed 's/[^[:alnum:]\.\_\-]/-/g')-dev
DOCKER_DIST_TAG?=$(shell $(GIT) describe --tags --always 2>/dev/null)
DOCKER_BUILDER?=$(DOCKER_PROJECT)
DOCKER_PLATFORMS?=linux/arm64,linux/amd64
DOCKER_NAME?=$(DOCKER_PROJECT)
DOCKER_PORT?=0

THIS_MAKEFILE:=$(firstword $(MAKEFILE_LIST))
SHELL:=$(BASH) -e -o pipefail
MKDIR:=mkdir -p
RM:=rm -rf

$(shell $(MKDIR) $(HOME)/.npm)

ifndef WITH_DEBUG
.SILENT:
endif

.DEFAULT_GOAL:=help

%/.:
	$(MKDIR) $@

.PHONY: bin
bin: $(shell cat $(THIS_MAKEFILE) | grep -E '^bin/[^:]+:' | cut -d: -f1)

bin/npm: $(THIS_MAKEFILE) | bin/. .install/docker/$(DOCKER_DEV_TAG)
	echo '$(DOCKER) run -u $$(id -u):$$(id -g) --rm -it -v $(HOME)/.npm:/.npm -v $$(dirname $$(dirname $$(readlink -f $$0))):/app -w /app $(DOCKER_REPOSITORY)/$(DOCKER_PROJECT):$(DOCKER_DEV_TAG) npm --no-update-notifier --cache /.npm "$$@"' > $@
	chmod u+x $@

bin/node: $(THIS_MAKEFILE) | bin/. .install/docker/$(DOCKER_DEV_TAG)
	echo '$(DOCKER) run -u $$(id -u):$$(id -g) --rm -it -v $$(dirname $$(dirname $$(readlink -f $$0))):/app -w /app $(DOCKER_REPOSITORY)/$(DOCKER_PROJECT):$(DOCKER_DEV_TAG) "$$@"' > $@
	chmod u+x $@

.PHONY: install
install: bin node_modules/.package-lock.json .install/docker/$(DOCKER_DEV_TAG) ## <Environment> Install all dependencies

.PHONY: reinstall
reinstall: ## <Environment> Clean all and reinstall all dependencies
	$(MAKE) clean
	$(MAKE) install

.install/docker/$(DOCKER_DEV_TAG): Dockerfile | .install/docker/.
	$(DOCKER) buildx create --name $(DOCKER_BUILDER) --platform $(DOCKER_PLATFORMS) --bootstrap &>/dev/null || true
	$(DOCKER) buildx build --builder $(DOCKER_BUILDER) --load -t $(DOCKER_REPOSITORY)/$(DOCKER_PROJECT):$(DOCKER_DEV_TAG) --target dev .
	> $@

node_modules/.package-lock.json: package-lock.json | bin/npm
	./bin/npm --no-update-notifier install --no-fund

.PHONY: start
start: install ## <Environment> Start HTTP server used to upload configuration files
	echo "Server successfully started, go to http://$$($(DOCKER) port $$($(DOCKER) run --name $(DOCKER_NAME) -p $(DOCKER_PORT):8080 -u $$(id -u):$$(id -g) -v $$(pwd):/app -w /app -d $(DOCKER_REPOSITORY)/$(DOCKER_PROJECT):$(DOCKER_DEV_TAG)) 8080 | head -n 1)!" 

.PHONY: stop
stop: ## <Environment> Stop HTTP server used to upload configuration files
	$(DOCKER) rm -f $(DOCKER_NAME) &>/dev/null || true

.PHONY: restart
restart: ## <Environment> Restart HTTP server used to upload configuration files
	$(MAKE) stop
	$(MAKE) start

.PHONY: dist
dist: | dist/$(DOCKER_DIST_TAG) ## <Build> Create dist directory according to current commit

dist/$(DOCKER_DIST_TAG): | dist/$(DOCKER_DIST_TAG)/. .install/docker/$(DOCKER_DEV_TAG)
	$(GIT) archive --worktree-attributes --format=tar $(DOCKER_DIST_TAG) | tar -x -C dist/$(DOCKER_DIST_TAG)
	$(DOCKER) run -u $$(id -u):$$(id -g) --rm -it -v $(HOME)/.npm:/.npm -v $$(pwd)/dist/$(DOCKER_DIST_TAG):/app -w /app $(DOCKER_REPOSITORY)/$(DOCKER_PROJECT):$(DOCKER_DEV_TAG) npm --cache /.npm --no-update-notifier install --no-fund --omit dev

.PHONY: docker
docker: dist/$(DOCKER_DIST_TAG)/docker.built

dist/$(DOCKER_DIST_TAG)/docker.built: | dist/$(DOCKER_DIST_TAG) ## <Build> Create docker image
	cd dist/$(DOCKER_DIST_TAG); \
	$(DOCKER) buildx create --name $(DOCKER_BUILDER) --platform $(DOCKER_PLATFORMS) --bootstrap &>/dev/null || true; \
	$(DOCKER) buildx build --builder $(DOCKER_BUILDER) --load -t $(DOCKER_REPOSITORY)/$(DOCKER_PROJECT):$(DOCKER_DIST_TAG) --target prod .
	> $@

.PHONY: docker/push
docker/push: | dist/$(DOCKER_DIST_TAG)/docker.built
	$(DOCKER) push $(DOCKER_REPOSITORY)/$(DOCKER_PROJECT):$(DOCKER_DIST_TAG)

.PHONY: clean/docker
clean/docker: ## <Cleaning> Delete all stuff related to docker
	for image in $$($(DOCKER) images --format "{{.Repository}}:{{.Tag}}" | grep -E "^$(DOCKER_REPOSITORY)/$(DOCKER_PROJECT):.+$$"); do \
		$(DOCKER) rm -f $$($(DOCKER) ps -a --format "{{.ID}}:{{.Image}}" | grep -E ":$${image}$$" | cut -d: -f1) 2>/dev/null || true; \
		$(DOCKER) rmi $$image; \
	done
	$(DOCKER) buildx rm $(DOCKER_BUILDER) 2>/dev/null || true

.PHONY: clean
clean: clean/docker ## <Cleaning> Delete all files, directories and docker images created at runtime
	$(GIT) clean -Xdf

.PHONY: help
help:
	sed -e '/#\{2\} /!d; s/^[^:]*: *\([^?:=]*[?:]*=[^#]*##\)/\1/; s/[?=:][^#]*##/:/; s/# *\([^#]*\)##/\1:/; s/\([^:?]*\): <\([^>]*\)> \(.*\)/\2:\1:\3/; s/\([^:]*\): \([^<]*.*\)/Misc.:\1:\2/' $(MAKEFILE_LIST) | \
	sort -t: -b -d -i | \
	awk 'BEGIN{FS=":"; section=""} { if ($$1 != section) { section=$$1; printf "\n\033[1m%s\033[0m\n", $$1 } printf "\t\033[92m%s\033[0m:%s\n", $$2, $$3 }' | \
	column -c2 -t -s:
