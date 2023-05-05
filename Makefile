SHELL=/bin/sh

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

# If CCACHE_CXX_COMPILER is defined, use ccache
ifdef CCACHE_CXX_COMPILER
CCACHE_SUPPORT += -DCMAKE_CXX_COMPILER=$(CCACHE_CXX_COMPILER)
endif

# If CCACHE_C_COMPILER is defined, use ccache
ifdef CCACHE_C_COMPILER
CCACHE_SUPPORT += -DCMAKE_C_COMPILER=$(CCACHE_C_COMPILER)
endif

# Internal
PATCH_DIR := $(abspath patches)
TMP_DIR := /tmp/slicer-flatpak-$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
SLICER_SOURCE_DIR := $(TMP_DIR)/Slicer
ITK_SOURCE_DIR:= $(TMP_DIR)/ITK
CTK_SOURCE_DIR:= $(TMP_DIR)/CTK
FLATPAK_DIR := $(CURDIR)/org.slicer.Slicer

all: \
    info \
    check-system-dependencies \
    check-flatpak-dependencies \
    analyze-slicer-dependencies \
    analyze-slicer-python-dependencies \
	analyze-ITK-remote-modules \
	analyze-ctk-dependencies\
    generate-flatpak-manifest \
    build-flatpak

info:
	@echo "################################################################################"
	@echo "#                                                                              #"
	@echo "#                  3D Slicer Flatpak Generator                                 #"
	@echo "#                                                                              #"
	@echo "################################################################################"
	@echo ""
	@echo "Project Configuration:"
	@echo "~~~~~~~~~~~~~~~~~~~~~~"
	@echo "SLICER_GIT_REPOSITORY: $(SLICER_GIT_REPOSITORY)"
	@echo "SLICER_GIT_TAG: $(SLICER_GIT_TAG)"
	@echo "PLATFORM_VERSION: $(PLATFORM_VERSION)"
	@echo "QTWEBENGINE_VERSION: $(QTWEBENGINE_VERSION)"
	@echo "SDK_VERSION: $(SDK_VERSION)"
	@echo ""
	@echo "CCACHE SUPPORT:"
	@echo "~~~~~~~~~~~~~~~~~"
	@echo "CCACHE_C_COMPILER: $(CCACHE_C_COMPILER)"
	@echo "CCACHE_CXX_COMPILER: $(CCACHE_CXX_COMPILER)"
ifeq ($(DEBUG),true)
	@echo "Debug Variables:"
	@echo "~~~~~~~~~~~~~~~~~"
	@echo "PATCH_DIR: $(PATCH_DIR)"
	@echo "TMP_DIR: $(TMP_DIR)"
	@echo "SLICER_SOUCE_DIR: $(SLICER_SOURCE_DIR)"
	@echo ""
endif


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
	$(Q)if command -v awk > /dev/null; then \
		echo "awk is installed"; \
	else \
		echo "ERROR: awk is not installed"; exit 1; \
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
		for patch in $$(ls $(PATCH_DIR)/Slicer); do git apply $(PATCH_DIR)/Slicer/$${patch}; done && \
		mkdir -p $(SLICER_SOURCE_DIR)/Release && \
		cmake -S . -B Release -DCMAKE_BUILD_TYPE:STRING=Release $(CCACHE_SUPPORT) 2&> Release/cmake.out && \
		cmake --build Release --target python-ensurepip && \
		$(SLICER_SOURCE_DIR)/Release/python-install/bin/PythonSlicer -m pip install PyYaml requirements-parser && \
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

analyze-ctk-dependencies: analyze-slicer-dependencies
	$(Q)cd $(TMP_DIR) && \
	mkdir CTK-deps -p && \
	git clone $$(cat $(TMP_DIR)/CTK.git.url) CTK
	$(Q)cd $(TMP_DIR)/CTK && \
	git checkout $$(cat $(TMP_DIR)/CTK.git.tag) && \
	for patch in $$(ls $(PATCH_DIR)/CTK); do git apply $(PATCH_DIR)/CTK/$${patch}; done && \
	mkdir -p $(CTK_SOURCE_DIR)/Release && \
	cmake -S . -B Release -DCMAKE_BUILD_TYPE:STRING=Release $(CCACHE_SUPPORT) -DCTK_USE_QTTESTING:BOOL=ON 2&> Release/cmake.out && \
	grep "GIT_REPOSITORY" Release/cmake.out | \
		awk -F= '{gsub("-- ", "", $$1); gsub("_GIT_REPOSITORY", "", $$1); print $$1 > "$(TMP_DIR)/CTK-deps/"$$1".git.dep"; print $$2 > "$(TMP_DIR)/CTK-deps/"$$1".git.dep"}' && \
	grep "GIT_TAG" Release/cmake.out | \
		awk -F= '{gsub("-- ", "", $$1); gsub("_GIT_TAG", "", $$1); print $$2 >> "$(TMP_DIR)/CTK-deps/"$$1".git.dep"}' && \
	grep "ARCHIVE_URL" Release/cmake.out | \
		awk -F= '{gsub("-- ", "", $$1); gsub("_ARCHIVE_URL", "", $$1); print $$1 > "$(TMP_DIR)/CTK-deps/"$$1".archive.dep"; print $$2 > "$(TMP_DIR)/CTK-deps/"$$1".archive.dep"}'
# Write dependency files
	$(Q)cd $(TMP_DIR)/CTK-deps && \
		for dep in *.git.dep; do \
			repo_url=`head -2 $$dep | tail -1 | sed 's/\.git//g'`; \
			repo_tag=`tail -1 $$dep`; \
			echo "$${repo_url}" > $(TMP_DIR)/CTK-deps/$${dep/%.git.dep/.git.url}; \
			echo "$${repo_tag}" > $(TMP_DIR)/CTK-deps/$${dep/%.git.dep/.git.tag}; \
		done
	# $(Q)cd $(TMP_DIR)/CTK-deps && \
	# 	for dep in *.archive.dep; do \
	# 		archive_url=`head -2 $$dep | tail -1`; \
	# 		echo "$${archive_url}" > $(TMP_DIR)/CTK-deps/$${dep/%.archive.dep/.archive.url}; \
	# 		echo "$${archive_url##*/}" > $(TMP_DIR)/CTK-deps/$${dep/%.archive.dep/.archive.filename}; \
	# 		curl -LJ $${archive_url} | sha256sum | cut -d' ' -f1 > $(TMP_DIR)/CTK-deps/$${dep%.archive.dep}.sha256; \
	# 	done

analyze-slicer-python-dependencies: analyze-slicer-dependencies
	$(Q)echo "Analyzing python dependencies..."
	for pythondep in $(SLICER_SOURCE_DIR)/Release/python*requirements.txt ; \
	do \
		$(SLICER_SOURCE_DIR)/Release/python-install/bin/PythonSlicer scripts/slicer-python-deps-generator.py -r $${pythondep} -o $(TMP_DIR)/$$(basename $${pythondep%.txt}) \
			--target-requirements $$(basename $${pythondep%-requirements.txt}) --yaml; \
	done

analyze-ITK-remote-modules: analyze-slicer-dependencies
	$(Q)echo "Analyzing python dependencies..."
	mkdir $(TMP_DIR)/ITK-Remote-Modules -p
	cd $(TMP_DIR) && git clone $$(cat $(TMP_DIR)/ITK.git.url) ITK
	cd $(ITK_SOURCE_DIR) && git checkout $$(cat $(TMP_DIR)/ITK.git.tag)
	$(eval ITK_BANNED_MODULES := ITKTubeTK) # Set the list of banned modules
	for file in $(ITK_SOURCE_DIR)/Modules/Remote/*.cmake; do \
		if echo "$(ITK_BANNED_MODULES)" | grep -qw $$(basename $$file .cmake); then \
			echo "Skipping module $$(basename $$file .cmake)"; \
		else \
			repo=$$(grep "^[\t ]*GIT_REPOSITORY" $$file | sed 's/GIT_REPOSITORY\s\{0,\}\$${git_protocol}:\/\/\([a-zA-Z0-9.\/:_-]*\)/https:\/\/\1/' | sed 's/^[ \t]*//'); \
			tag=$$(grep "^[\t ]*GIT_TAG" $$file | sed 's/GIT_TAG\s\{0,\}//'); \
			url_file=$$(basename $$file .cmake); \
			url_file=ITK-Remote-$${url_file}.git.url; \
			tag_file=$$(basename $$file .cmake); \
			tag_file=ITK-Remote-$${tag_file}.git.tag; \
			echo "$$repo" > $(TMP_DIR)/ITK-Remote-Modules/$$url_file; \
			echo "$$tag" > $(TMP_DIR)/ITK-Remote-Modules/$$tag_file; \
		fi; \
	done

generate-patch-slicer-external-ctk: analyze-ctk-dependencies
	$(Q)echo "Generating patch for Slicer/External_CTK.cmake..."

	$(Q)cat $(TMP_DIR)/Slicer/SuperBuild/External_CTK.cmake | while IFS= read -r line; do \
		if echo "$$line" | grep -q "#<CTK_TEMPLATED_FLAGS>"; then \
			for dep in $(TMP_DIR)/CTK-deps/*.git.url; do \
				echo "-D$$(basename $${dep%.git.*})_GIT_REPOSITORY:STRING="'file://$${FLATPAK_BUILDER_BUILDDIR}/dependencies/'"$$(basename $${dep%.*})" ; \
			done ; \
		else \
			printf '%s\n' "$$line" ; \
		fi ; \
	done > $(TMP_DIR)/Slicer/SuperBuild/External_CTK.cmake.tmp
	$(Q)mv $(TMP_DIR)/Slicer/SuperBuild/External_CTK.cmake.tmp $(TMP_DIR)/Slicer/SuperBuild/External_CTK.cmake
	$(Q)cd $(TMP_DIR)/Slicer && git diff --patch > $(FLATPAK_DIR)/Generated_CTK_SuperBuild.patch

# Generate the Flatpak manifest using a template and the corresponding
# dependencies
generate-flatpak-manifest: analyze-slicer-python-dependencies analyze-ctk-dependencies generate-patch-slicer-external-ctk
	$(Q)echo "Generating flatpak manifest..."

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
				echo "      - type: file" ; \
				echo "        url: $$(cat $$dep)" ; \
				echo "        sha256: $$(cat $${dep%%.archive.url}.sha256)" ; \
				echo "        dest: dependencies" ; \
			done ; \
		elif echo "$$line" | grep -q "<CMAKE_ARCHIVE_DEPENDENCY_FLAGS>"; then \
			for dep in $(TMP_DIR)/*.archive.url; do \
				echo "        -DSlicer_$$(basename $${dep%.archive.*})_ARCHIVE_URL:STRING="'$${FLATPAK_BUILDER_BUILDDIR}/dependencies/'"$$(cat $${dep%.archive.url}.archive.filename)" ; \
			done ; \
		elif echo "$$line" | grep -q "<CMAKE_PYTHON_DEPENDENCY_FLAGS>"; then \
			for dep in $(TMP_DIR)/python-*.yaml; do \
				echo "        -DSlicer_$$(basename $${dep%*-requirements.yaml})_WHEEL_PATH:STRING="'$${FLATPAK_BUILDER_BUILDDIR}/'"$$(grep dest: $$dep | head -1 | tr -d ' '| cut -d: -f 2)" ; \
			done ; \
		elif echo "$$line" | grep -q "<ITK_REMOTE_MODULE_DEPENDENCIES>"; then \
			for dep in $(TMP_DIR)/ITK-Remote-Modules/*.git.url; do \
				echo "      - type: git" ; \
				echo "        url: $$(cat $$dep)" ; \
				echo "        tag: $$(cat $${dep%%.url}.tag)" ; \
				echo "        dest: dependencies/ITK-Remote-Modules/$$(basename $${dep%.*})" ; \
			done ; \
		elif echo "$$line" | grep -q "<CTK_DEPENDENCIES>"; then \
			for dep in $(TMP_DIR)/CTK-deps/*.git.url; do \
				echo "      - type: git" ; \
				echo "        url: $$(cat $$dep)" ; \
				echo "        tag: $$(cat $${dep%%.url}.tag)" ; \
				echo "        dest: dependencies/CTK-dependencies/$$(basename $${dep%.*})" ; \
			done ; \
		else \
			printf '%s\n' "$$line" ; \
		fi ; \
	done > org.slicer.Slicer/org.slicer.Slicer.yaml

	for pythondep in $(SLICER_SOURCE_DIR)/Release/python*requirements.txt ; \
	do \
		sed 's/^/      /' $(TMP_DIR)/$$(basename $${pythondep%.txt}).yaml >> org.slicer.Slicer/org.slicer.Slicer.yaml; \
	done;

# Build Flatpak
build-flatpak: info
	$(Q)echo "Building Flatpak..."
# Put code here to build the Flatpak

# Clean
clean:
	$(Q)echo "Cleaning generated files..."
	$(Q)rm -rf $(TMP_DIR)
	$(Q)rm -rf $(RANDOM_DIR)
