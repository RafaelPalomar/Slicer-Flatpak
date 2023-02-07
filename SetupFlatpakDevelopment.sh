#!/bin/env bash
set -eo pipefail

DEPENDECIES=("flatpak" "flatpak-builder" "git")
LOG_FILE="$PWD/set_build.log"
ERR_FILE="$PWD/set_build.err"
SLICER_DEFAULT_TAG="v5.2.0"
SLICER_REPOSITORY="https://github.com/Slicer/Slicer.git"
ERR_COLOR='\033[01;31m'  # Red for error messages
NO_COLOR='\033[0m'      # Revert terminal back to no color
WARN_COLOR='\033[33;01m'
INFO_COLOR='\033[01;33m' # Yellow for notes


tag="$SLICER_DEFAULT_TAG"

err(){
    echo -e "[$(date +'%b %d %X')] ${ERR_COLOR}$@${NO_COLOR}" 1>&2
	exit 1
}

warn(){
	echo -e "[$(date +'%b %d %X')] ${WARN_COLOR}$@${NO_COLOR}"
}

info(){
    echo -e "[$(date +'%b %d %X')] $@"
}

ok(){
    echo -e "[$(date +'%b %d %X')] ${INFO_COLOR}$@${NO_COLOR}"
}

check_dependencies(){
	local is_missing
	is_missing=0
	for package in ${DEPENDECIES[*]}; do
		if command -v "${package}" > /dev/null; then
			is_missing="1" 
			warn "$package is not installed"
		fi
	done
	
	[[ $is_missing == 1 ]] && err "Missing dependencies where found" 
}

main(){
	info "Donwloading Slicer"
	# https://stackoverflow.com/questions/791959/download-a-specific-tag-with-git
	#git clone "$SLICER_REPOSITORY" --origin "Slicer"

	info "Downloading Slicer dependencies"

	info "Checking dependencies"
	check_dependencies

}

[ "$0" == "$BASH_SOURCE" ] && main $@
