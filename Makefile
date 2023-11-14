.PHONY: all clean

.DEFAULT_GOAL:=all

MAKEFILE:=$(abspath $(lastword $(MAKEFILE_LIST)))
MAKEDIR:=$(dir $(MAKEFILE))
ROOT:=$(patsubst %/,%,$(MAKEDIR))
OBJ:=$(ROOT)/obj

vpath

EXT_ADOC:=$(foreach adoc,$(ADOC),$(OBJ)/ext/$(notdir $(adoc)))
vpath %.adoc $(foreach adoc,$(ADOC),$(dir $(adoc)))

EXT_PNG:=$(foreach png,$(PNG),$(OBJ)/images/$(notdir $(png)))
vpath %.png $(foreach png,$(PNG),$(dir $(png)))

BUILDER:=podman
IMAGE:=quay.io/redhat-cop/ubi8-asciidoctor:v2.1
LANGUAGE:=en_US

ifndef CONFIG
$(error CONFIG must be supplied with the filename of your test report JSON config)
endif

REPORT_DATETIME:=$(shell date -u -Iseconds)
REPORT_DATE:=$(shell date -u -I)
GIT_HASH:=$(shell jq -r .githash "$(CONFIG)" | cut -c -8)
TITLE:=$(shell jq -r .title "$(CONFIG)")
SUBTITLE:=$(shell jq -r .subtitle "$(CONFIG)")
SUBJECT:=$(TITLE): $(SUBTITLE)
DESCRIPTION:=$(SUBTITLE)

ADOC_ATTRIBUTES:=$(foreach attribute,$(ATTRIBUTES),--attribute="$(attribute)")

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
    --attribute=revdate="$(date +'%Y-%m-%d')" \
    $(ADOC_ATTRIBUTES)

define this-user-id =
$(shell id -u)
endef

define build-pdf-podman =
podman run --rm --name asciidoctor \
    --user="$(this-user-id)" \
    --userns=keep-id \
    -v "$(shell dirname $@):/documents:Z" \
    -w "/documents" \
    $(IMAGE) \
    $(ADOC_PDF) -o "$(shell basename $@)" "$(shell basename $<)"
endef

define build-pdf-docker =
docker run --rm --name asciidoctor \
    --user "$(this-user-id)" \
    -v "$(shell dirname $@):/documents:Z" \
    -w "/documents" \
    $(IMAGE) \
    $(ADOC_PDF) -o "$(shell basename $@)" "$(shell basename $<)"
endef

define build-pdf-native =
$(ADOC_PDF) -o "$@" "$<"
endef

$(OBJ):
	@echo +++++ preparing $@ +++++
	mkdir -p $@
	for DIRNAME in src pdf-assets vars; do cp -r $(ROOT)/$${DIRNAME} $(OBJ)/; done
	@echo

$(OBJ)/ext: | $(OBJ)
	@echo +++++ preparing $@ +++++
	mkdir -p $@
	@echo

$(OBJ)/ext/%.adoc: %.adoc | $(OBJ)/ext
	@echo +++++ staging $@ +++++
	cp $< $@
	@echo

$(OBJ)/images/%.png: %.png | $(OBJ)
	@echo +++++ staging $@ +++++
	cp $< $@
	@echo

$(OBJ)/test-report.adoc: $(EXT_ADOC) $(EXT_PNG) $(CONFIG) $(JUNIT) | $(OBJ) $(OBJ)/ext
	@echo +++++ generating $@ +++++
	echo 'include::src/test-report-head.adoc[]' >$@
	echo >>$@
	for ADOC in $(EXT_ADOC); do printf 'include::ext/%s[]\n\n' "$$(basename "$$ADOC")"; done >>$@
	python3 -m testdrive.asciidoc $(shell dirname $@) $(CONFIG) $(JUNIT) >>$@
	echo >>$@
	echo 'include::src/test-report-tail.adoc[]' >>$@
	@echo

$(PDF): $(OBJ)/test-report.adoc $(CONFIG)
	@echo +++++ building $@ using builder $(BUILDER) +++++
	$(build-pdf-$(BUILDER))
	@echo

all: $(PDF)

clean:
	@rm -rf "$(OBJ)/"
