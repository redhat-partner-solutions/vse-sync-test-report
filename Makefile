.PHONY: all clean

.DEFAULT_GOAL:=all

MAKEFILE:=$(abspath $(lastword $(MAKEFILE_LIST)))
MAKEDIR:=$(dir $(MAKEFILE))
ROOT:=$(patsubst %/,%,$(MAKEDIR))
SRC:=src
OBJ:=obj

BUILDER:=podman
IMAGE:=quay.io/redhat-cop/ubi8-asciidoctor:v1.3
LANGUAGE:=en_US

ifndef CONFIG
$(error CONFIG must be supplied with the filename of your test report JSON config)
endif

REPORT_DATETIME:=$(shell date -u -Iseconds)
REPORT_DATE:=$(shell date -u -I)
GIT_HASH:=$(shell jq -r .githash "$(CONFIG)" | cut -c -8)
SUBJECT:=$(shell jq -r .subject "$(CONFIG)")
DESCRIPTION:=$(shell jq -r .description "$(CONFIG)")
BRIEF:=$(shell jq -r .brief "$(CONFIG)")

ifdef TIMESTAMP_FILENAME
PDF:=$(OBJ)/test-report_$(shell echo $(REPORT_DATETIME) | sed -e s/://g -e s/-//g -e s/+0000/Z/).pdf
else
PDF:=$(OBJ)/test-report.pdf
endif

ADOC_PDF:=\
    asciidoctor-pdf \
    -r asciidoctor-diagram \
    --failure-level=WARN \
    --attribute=lang="$(LANGUAGE)" \
    --attribute=reportdatetime="$(REPORT_DATETIME)" \
    --attribute=reportdate="$(REPORT_DATE)" \
    --attribute=githash="$(GIT_HASH)" \
    --attribute=subject="$(SUBJECT)" \
    --attribute=description="$(DESCRIPTION)" \
    --attribute=brief="$(BRIEF)"

define this-user-id =
$(shell id -u)
endef

define build-pdf-podman =
podman run --rm --name asciidoctor \
    --user="$(this-user-id)" \
    --userns=keep-id \
    -v "$(ROOT)/:/documents:Z" \
    -w "/documents" \
    $(IMAGE) \
    $(ADOC_PDF) -o "$@" "$<"
endef

define build-pdf-docker =
docker run --rm --name asciidoctor \
    --user "$(this-user-id)" \
    -v "$(ROOT)/:/documents:Z" \
    -w "/documents" \
    $(IMAGE) \
    $(ADOC_PDF) -o "$@" "$<"
endef

define build-pdf-native =
$(ADOC_PDF) -o "$@" "$<"
endef

$(OBJ)/test-report-head.adoc: $(SRC)/test-report-head.adoc
	@echo +++++ generating $@ +++++
	mkdir -p $(shell dirname $@)
	cp $< $@

$(OBJ)/test-report-body.adoc: $(CONFIG) $(JUNIT)
	@echo +++++ generating $@ +++++
	mkdir -p $(shell dirname $@)/images
	python3 -m testdrive.asciidoc $(shell dirname $@) $(CONFIG) $(JUNIT) >$@

$(OBJ)/test-report-tail.adoc: $(SRC)/test-report-tail.adoc
	@echo +++++ generating $@ +++++
	mkdir -p $(shell dirname $@)
	cp $< $@

$(OBJ)/test-report.adoc: $(OBJ)/test-report-head.adoc $(OBJ)/test-report-body.adoc $(OBJ)/test-report-tail.adoc
	@echo +++++ generating $@ +++++
	@cat $+ >$@

$(PDF): $(OBJ)/test-report.adoc $(CONFIG)
	@echo +++++ building $@ using builder $(BUILDER) +++++
	$(build-pdf-$(BUILDER))

all: $(PDF)

clean:
	@rm -rf "$(OBJ)/"
