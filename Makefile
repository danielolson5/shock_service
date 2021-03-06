TOP_DIR = ../..
TARGET ?= /kb/deployment
DEPLOY_RUNTIME = /kb/runtime
SERVICE = shock_service
SERVICE_DIR = $(TARGET)/services/$(SERVICE)

GO_TMP_DIR = /tmp/go_build.tmp

PRODUCTION = 0 

ifeq ($(PRODUCTION), 1)
	SHOCK_SITE = /disk0/site
	SHOCK_DATA = /disk0/data
	SHOCK_LOGS = $(SERVICE_DIR)/logs/shock
	MONGO_HOST = mongodb.kbase.us
	MONGO_DB = ShockDB

	TPAGE_ARGS = --define kb_top=$(TARGET) \
	--define kb_runtime=$(DEPLOY_RUNTIME) \
	--define api_url=https://kbase.us/services/shock-api	\
	--define api_port=7044 \
	--define site_dir=$(SHOCK_SITE) \
	--define data_dir=$(SHOCK_DATA) \
	--define logs_dir=$(SHOCK_LOGS) \
	--define mongo_host=$(MONGO_HOST) \
	--define mongo_db=$(MONGO_DB) \
	--define kb_runas_user=$(SERVICE_USER)
else
	SHOCK_SITE = /mnt/Shock/site
	SHOCK_DATA = /mnt/Shock/data
	SHOCK_LOGS = /mnt/Shock/logs
	MONGO_HOST = localhost
	MONGO_DB = ShockDBtest

	TPAGE_ARGS = --define kb_top=$(TARGET) \
	--define kb_runtime=$(DEPLOY_RUNTIME) \
	--define api_port=7078 \
	--define site_dir=$(SHOCK_SITE) \
	--define data_dir=$(SHOCK_DATA) \
	--define logs_dir=$(SHOCK_LOGS) \
	--define mongo_host=$(MONGO_HOST) \
	--define mongo_db=$(MONGO_DB) \
	--define kb_runas_user=$(SERVICE_USER)
endif

include $(TOP_DIR)/tools/Makefile.common

.PHONY : test

all: initialize prepare build-shock

build-shock: $(BIN_DIR)/shock-server

$(BIN_DIR)/shock-server: Shock/shock-server/main.go
	rm -rf $(GO_TMP_DIR)
	mkdir -p $(GO_TMP_DIR)/src/github.com/MG-RAST
	cp -r Shock $(GO_TMP_DIR)/src/github.com/MG-RAST/
	export GOPATH=$(GO_TMP_DIR); go get -v github.com/MG-RAST/Shock/...
	cp Shock/Makefile $(GO_TMP_DIR)/
	cd $(GO_TMP_DIR)/; export GOPATH=$(GO_TMP_DIR); make install
	cp $(GO_TMP_DIR)/bin/shock-server $(BIN_DIR)/shock-server
	cp $(GO_TMP_DIR)/bin/shock-client $(BIN_DIR)/shock-client

deploy: deploy-libs deploy-client deploy-service

deploy-libs:
	rsync --exclude '*.bak' -arv Shock/libs/. $(TARGET)/lib/.

deploy-client: all
	cp $(BIN_DIR)/shock-client $(TARGET)/bin/shock-client

deploy-service: all
	cp $(BIN_DIR)/shock-server $(TARGET)/bin
	$(TPAGE) $(TPAGE_ARGS) shock.cfg.tt > shock.cfg

	mkdir -p $(SHOCK_SITE) $(SHOCK_DATA) $(SHOCK_LOGS)
	cp -r $(GO_TMP_DIR)/src/github.com/MG-RAST/Shock/shock-server/site/* $(SHOCK_SITE)/

	mkdir -p $(SERVICE_DIR) $(SERVICE_DIR)/conf $(SERVICE_DIR)/logs/shock $(SERVICE_DIR)/data/temp
	cp -v shock.cfg $(SERVICE_DIR)/conf/shock.cfg
	$(TPAGE) $(TPAGE_ARGS) service/start_service.tt > $(SERVICE_DIR)/start_service
	chmod +x $(SERVICE_DIR)/start_service
	$(TPAGE) $(TPAGE_ARGS) service/stop_service.tt > $(SERVICE_DIR)/stop_service
	chmod +x $(SERVICE_DIR)/stop_service

deploy-upstart:
	chown -R $(SERVICE_USER) $(SHOCK_SITE)
	chown -R $(SERVICE_USER) $(SHOCK_DATA)
	chown -R $(SERVICE_USER) $(SHOCK_LOGS)
ifeq ($(PRODUCTION), 1)
	$(TPAGE) $(TPAGE_ARGS) init/shock.conf.tt > /etc/init/shock.conf
else
	$(TPAGE) $(TPAGE_ARGS) init/shock_test.conf.tt > /etc/init/shock.conf
endif

fix-dates:
	mongo $(MONGO_HOST):27017/$(MONGO_DB) fix_dates.js 

initialize:
	git submodule init
	git submodule update

prepare: lib/Bio/KBase/Shock.pm

lib/Bio/KBase/Shock.pm:
	cd lib; ./prepare.sh

clean:
	rm -rf $(GO_TMP_DIR)
	rm -f $(BIN_DIR)/shock-client $(BIN_DIR)/shock-server
	cd lib; ./prepare.sh clean
	rm -rf

# Test Section
TESTS = $(wildcard test/*.t)

test:
	# run each test
	for t in $(TESTS) ; do \
		if [ -f $$t ] ; then \
			$(DEPLOY_RUNTIME)/bin/perl $$t ; \
			if [ $$? -ne 0 ] ; then \
				exit 1 ; \
			fi \
		fi \
	done

