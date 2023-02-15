# Slicer Git Repository and Tag
SLICER_GIT_REPOSITORY ?= https://github.com/Slicer/Slicer
SLICER_GIT_TAG ?= main

# Dependency Versions
PLATFORM_VERSION ?= 5.15
QTWEBENGINE_VERSION ?= 5.15-22.08
SDK_VERSION ?= $(PLATFORM_VERSION)


# Debug Variable
DEBUG ?= false

ifneq ($(DEBUG),false)
	Q=
else
	Q=@
endif

all: info check-system-dependencies check-flatpak-dependencies generate-flatpak-manifest build-flatpak

info:
	@echo "################################################################################"
	@echo "#                                                                              #"
	@echo "#                  3D Slicer Flatpak Generator                                 #"
	@echo "#                                                                              #"
	@echo "################################################################################"
	@echo ""
	@echo "Variables:"
	@echo "SLICER_GIT_REPOSITORY: $(SLICER_GIT_REPOSITORY)"
	@echo "SLICER_GIT_TAG: $(SLICER_GIT_TAG)"
	@echo "PLATFORM_VERSION: $(PLATFORM_VERSION)"
	@echo "QTWEBENGINE_VERSION: $(QTWEBENGINE_VERSION)"
	@echo "SDK_VERSION: $(SDK_VERSION)"
	@echo ""

# Check System Dependencies
check-system-dependencies: info
	$(Q)echo "Checking system dependencies..."
	$(Q)if command -v helm > /dev/null; then \
		echo "Helm is installed"; \
	else \
		echo "ERROR: Helm is not installed"; exit 1; \
	fi
	$(Q)if command -v flatpak > /dev/null; then \
		echo "Flatpak is installed"; \
	else \
		echo "ERROR: Flatpak is not installed"; exit 1; \
	fi
	$(Q)if command -v flatpak-builder > /dev/null; then \
		echo "Flatpak builder is installed"; \
	else \
		echo "ERROR: Flatpak builder is not installed"; exit 1; \
	fi

# Check Flatpak Dependencies
check-flatpak-dependencies: info
	$(Q)echo "Checking flatpak dependencies..."
	$(Q)if ! flatpak list --app --columns ref | grep -q "io.qt.qtwebengine.BaseApp/x86_64/$(QTWEBENGINE_VERSION)"; then \
		echo "ERROR: io.qt.qtwebengine.BaseApp/x86_64/$(QTWEBENGINE_VERSION) is not installed"; \
		echo "To install, run: flatpak install io.qt.qtwebengine.BaseApp/x86_64/$(QTWEBENGINE_VERSION)"; exit 1; \
	else \
		echo "io.qt.qtwebengine.BaseApp/x86_64/$(QTWEBENGINE_VERSION) is installed"; \
	fi

# Variables
PATCH_DIR := $(abspath patches)
DEPS_DIR := $(abspath slicer-dependencies)
TMP_DIR := /tmp/slicer-flatpak-$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)

# Generate Flatpak Manifest
generate-flatpak-manifest: check-flatpak-dependencies
	$(Q)echo "Analyzing Slicer dependencies..."
	$(Q)mkdir -p $(TMP_DIR)
	$(Q)mkdir -p $(DEPS_DIR)
	$(Q)cd $(TMP_DIR) && \
		git clone --depth=1 $(SLICER_GIT_REPOSITORY) -b $(SLICER_GIT_TAG) && \
		cd Slicer && \
		git apply $(PATCH_DIR)/01-ENH-Print-repo-tag.patch && \
		mkdir -p Release && \
		cd Release && \
		cmake -S .. -B . -DCMAKE_BUILD_TYPE:STRING=Release 2&> cmake.out && \
		grep "GIT_REPOSITORY" cmake.out | awk -F= '{gsub("-- Slicer_", "", $$1); gsub("_GIT_REPOSITORY", "", $$1); print $$1 > "$(DEPS_DIR)/"$$1".deps"; print $$2 > "$(DEPS_DIR)/"$$1".deps"}' && \
		grep "GIT_TAG" cmake.out | awk -F= '{gsub("-- Slicer_", "", $$1); gsub("_GIT_TAG", "", $$1); print $$2 >> "$(DEPS_DIR)/"$$1".deps"}'
	$(Q)cd $(DEPS_DIR) && \
		for dep in *.deps; do \
			repo_url=`head -2 $$dep | tail -1 | sed 's/\.git//g'`; \
			repo_tag=`tail -1 $$dep`; \
			echo "$${repo_url}" > $${dep/%.deps/.url}; \
			echo "$${repo_tag}" > $${dep/%.deps/.tag}; \
		done
	$(Q)cd $(DEPS_DIR) && \
		for i in *.url; do \
			curl -LJ $$(cat $$i) > $(TMP_DIR)/$${i%.url}.tar.gz; \
			sha256sum $(TMP_DIR)/$${i%.url}.tar.gz | cut -d' ' -f1 > $${i%.url}.sha256; \
		done
	$(Q)cat templates/org.slicer.Slicer.yaml | while IFS= read -r line; do \
		if echo "$$line" | grep -q "<SLICER_DEPENDENCIES>"; then \
			for dep in $(DEPS_DIR)/*.url; do \
				echo "      - type: git" ; \
				echo "        url: $$(cat $$dep)" ; \
				echo "        tag: $$(cat $${dep%%.url}.tag)" ; \
			done ; \
		else \
			printf '%s\n' "$$line" ; \
		fi ; \
	done > org.slicer.Slicer/org.slicer.Slicer.yaml


	$(Q)echo "Generating flatpak manifest..."

# Build Flatpak
build-flatpak: info
	$(Q)echo "Building Flatpak..."
# Put code here to build the Flatpak

# Clean
clean:
	$(Q)echo "Cleaning generated files..."
	$(Q)rm -rf $(DEPS_DIR)
	$(Q)rm -rf $(RANDOM_DIR)

.PHONY: check-system-dependencies check-flatpak-dependencies generate-flatpak-manifest build-flatpak

