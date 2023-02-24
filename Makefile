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

# Strip level function
# This is an utility function to selectively determine the directory strip level
# for different dependencies. This is needed due to the fact that the 1st level
# directory name does not match the expected name by the build system. An ideal
# scenario would be that the flatpak-builder allows to skip the archive
# extraction (whic is not the case), then the build system would take care of it.
# TDLR: A needed hack until flatpak-builder has functionality to skip archive
# extraction (which is expected by the Slicer superbuild)
define get_strip_level
if echo "$(1)" | grep -qw "OpenSSL"; then echo 2; else echo 1; fi
endef

all: info check-system-dependencies check-flatpak-dependencies analyze-slicer-dependencies generate-flatpak-manifest build-flatpak

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
TMP_DIR := /tmp/slicer-flatpak-$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
SLICER_SOURCE_DIR := $(TMP_DIR)/Slicer

# Pull 3D Slicer on the provided version and analyze its
# build dependencies. While most dependencies are handled
# as git dependencies in Slicer, CTKAppLauncher is handled
# as an arhive file.
analyze-slicer-dependencies: check-flatpak-dependencies
	$(Q)echo "Analyzing Slicer dependencies..."
	$(Q)mkdir -p $(TMP_DIR)
# Clone, patch and filter GIT Slicer dependencies
	$(Q)cd $(TMP_DIR) && \
		git clone --depth=1 $(SLICER_GIT_REPOSITORY) -b $(SLICER_GIT_TAG) && \
		cd $(SLICER_SOURCE_DIR) && \
		for patch in $$(ls $(PATCH_DIR)); do git apply $(PATCH_DIR)/$${patch}; done && \
		mkdir -p $(SLICER_SOURCE_DIR)/Release && \
		cmake -S . -B Release -DCMAKE_BUILD_TYPE:STRING=Release 2&> Release/cmake.out && \
		grep "GIT_REPOSITORY" Release/cmake.out | \
			awk -F= '{gsub("-- Slicer_", "", $$1); gsub("_GIT_REPOSITORY", "", $$1); print $$1 > "$(TMP_DIR)/"$$1".git.dep"; print $$2 > "$(TMP_DIR)/"$$1".git.dep"}' && \
		grep "GIT_TAG" Release/cmake.out | \
			awk -F= '{gsub("-- Slicer_", "", $$1); gsub("_GIT_TAG", "", $$1); print $$2 >> "$(TMP_DIR)/"$$1".git.dep"}' && \
		grep "ARCHIVE_URL" Release/cmake.out | \
			awk -F= '{gsub("-- Slicer_", "", $$1); gsub("_ARCHIVE_URL", "", $$1); print $$1 > "$(TMP_DIR)/"$$1".archive.dep"; print $$2 > "$(TMP_DIR)/"$$1".archive.dep"}'
# Write dependency files
	$(Q)cd $(TMP_DIR) && \
		for dep in *.git.dep; do \
			repo_url=`head -2 $$dep | tail -1 | sed 's/\.git//g'`; \
			repo_tag=`tail -1 $$dep`; \
			echo "$${repo_url}" > $(TMP_DIR)/$${dep/%.git.dep/.git.url}; \
			echo "$${repo_tag}" > $(TMP_DIR)/$${dep/%.git.dep/.git.tag}; \
		done
	$(Q)cd $(TMP_DIR) && \
		for dep in *.archive.dep; do \
			archive_url=`head -2 $$dep | tail -1`; \
			echo "$${archive_url}" > $(TMP_DIR)/$${dep/%.archive.dep/.archive.url}; \
			echo "$${archive_url##*/}" > $(TMP_DIR)/$${dep/%.archive.dep/.archive.filename}; \
			curl -LJ $${archive_url} | sha256sum | cut -d' ' -f1 > $(TMP_DIR)/$${dep%.archive.dep}.sha256; \
		done
	#For reference: https://superuser.com/questions/790560/variables-in-gnu-make-recipes-is-that-possible
	# $(Q)$(eval CTKAPPLAUNCHER_VERSION=`cat $(SLICER_SOURCE_DIR)/SuperBuild/External_CTKAPPLAUNCHER.cmake | grep -E 'set.launcher_version' | sed 's/[^0-9\.]//g'`)
	# $(Q)$(eval CTKAPPLAUNCHER_FILENAME=`echo CTKAppLauncher-$(CTKAPPLAUNCHER_VERSION)-linux-i386.tar.gz`)
	# $(Q)$(eval CTKAPPLAUNCHER_URL=`echo https://github.com/commontk/AppLauncher/releases/download/v$(CTKAPPLAUNCHER_VERSION)/$(CTKAPPLAUNCHER_FILENAME)`)
	# $(Q)curl -LJ $(CTKAPPLAUNCHER_URL) > $(TMP_DIR)/$(CTKAPPLAUNCHER_FILENAME)
	# $(Q)$(eval CTKAPPLAUNCHER_SHA256=`sha256sum $(TMP_DIR)/$(CTKAPPLAUNCHER_FILENAME) | cut -d' ' -f1'`)

# Generate the Flatpak manifest using a template and the corresponding
# dependencies
generate-flatpak-manifest: analyze-slicer-dependencies
	$(Q)echo "Generating flatpak manifest..."

# Slicer dependencies
	$(Q)cat templates/org.slicer.Slicer.yaml | while IFS= read -r line; do \
		if echo "$$line" | grep -q "<SLICER_GIT_DEPENDENCIES>"; then \
			for dep in $(TMP_DIR)/*.git.url; do \
				echo "      - type: git" ; \
				echo "        url: $$(cat $$dep)" ; \
				echo "        tag: $$(cat $${dep%%.url}.tag)" ; \
				echo "        dest: dependencies/$$(basename $${dep%.*})" ; \
			done ; \
		elif echo "$$line" | grep -q "<CMAKE_GIT_DEPENDENCY_FLAGS>"; then \
			for dep in $(TMP_DIR)/*.git.url; do \
				echo "        -DSlicer_$$(basename $${dep%.git.*})_GIT_REPOSITORY:STRING="'file://$${FLATPAK_BUILDER_BUILDDIR}/dependencies/'"$$(basename $${dep%.*})" ; \
			done ; \
		elif echo "$$line" | grep -q "<SLICER_ARCHIVE_DEPENDENCIES>"; then \
			for dep in $(TMP_DIR)/*.archive.url; do \
				strip_level=`$(call get_strip_level, $${dep%.archive.url})` ; \
				echo "      - type: archive" ; \
				echo "        url: $$(cat $$dep)" ; \
				echo "        sha256: $$(cat $${dep%%.archive.url}.sha256)" ; \
				echo "        dest: dependencies/$$(cat $${dep%.archive.url}.archive.filename)" ; \
				echo "        strip-components: $${strip_level}"  ; \
			done ; \
		elif echo "$$line" | grep -q "<CMAKE_ARCHIVE_DEPENDENCY_FLAGS>"; then \
			for dep in $(TMP_DIR)/*.archive.url; do \
				echo "        -DSlicer_$$(basename $${dep%.archive.*})_ARCHIVE_URL:STRING="'$${FLATPAK_BUILDER_BUILDDIR}/dependencies/'"$$(cat $${dep%.archive.url}.archive.filename)" ; \
			done ; \
		else \
			printf '%s\n' "$$line" ; \
		fi ; \
	done > org.slicer.Slicer/org.slicer.Slicer.yaml


# Build Flatpak
build-flatpak: info
	$(Q)echo "Building Flatpak..."
# Put code here to build the Flatpak

# Clean
clean:
	$(Q)echo "Cleaning generated files..."
	$(Q)rm -rf $(TMP_DIR)
	$(Q)rm -rf $(RANDOM_DIR)

.PHONY: check-system-dependencies check-flatpak-dependencies generate-flatpak-manifest build-flatpak

