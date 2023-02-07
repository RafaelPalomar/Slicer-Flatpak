#!/bin/bash

set -eo pipefail

# See https://discourse.slicer.org/t/interest-to-create-flatpak-for-3d-slicer-have-issue-with-guisupportqtopengl-not-found/16532

PROG=$(basename $0)

SLICER_DEPENDENCIES_DIR=/tmp

#
# Dependencies associated with Slicer d234b7ee9 from 2021.03.17
# See https://github.com/Slicer/Slicer/commit/d234b7ee9dd6f7ab7ed7d141c08db05f9e20a3d9
#

slicer_git_dependencies_file=${SLICER_DEPENDENCIES_DIR}/slicer_git_dependencies
cat << EOF > ${slicer_git_dependencies_file}
Slicer_zlib_GIT_REPOSITORY=git://github.com/commontk/zlib.git
Slicer_zlib_GIT_TAG=66a753054b356da85e1838a081aa94287226823e
Slicer_curl_GIT_REPOSITORY=git://github.com/Slicer/curl.git
Slicer_curl_GIT_TAG=ca5fe8e63df7faea0bfb988ef3fe58f538e6950b
Slicer_CTKAppLauncherLib_GIT_REPOSITORY=git://github.com/commontk/AppLauncher.git
Slicer_CTKAppLauncherLib_GIT_TAG=1367de4c6efde0c11e87835fb7245ea2b05074aa
Slicer_bzip2_GIT_REPOSITORY=git://github.com/commontk/bzip2.git
Slicer_bzip2_GIT_TAG=0e735f23032ececcf52ed49b27928390fff28e50
Slicer_LZMA_GIT_REPOSITORY=git://github.com/Slicer/lib_lzma.git
Slicer_LZMA_GIT_TAG=v5.2.2
Slicer_sqlite_GIT_REPOSITORY=git://github.com/azadkuh/sqlite-amalgamation.git
Slicer_sqlite_GIT_TAG=3.30.1
Slicer_python_GIT_REPOSITORY=git://github.com/python-cmake-buildsystem/python-cmake-buildsystem.git
Slicer_python_GIT_TAG=dca8bee81e29b452560bd969d67e7d08237e23d6
Slicer_VTK_GIT_REPOSITORY=git://github.com/slicer/VTK.git
Slicer_VTK_GIT_TAG=1076d8bc00f12c49af4e35a3e0e58beae6ad361b
Slicer_teem_GIT_REPOSITORY=git://github.com/Slicer/teem
Slicer_teem_GIT_TAG=e4746083c0e1dc0c137124c41eca5d23adf73bfa
Slicer_DCMTK_GIT_REPOSITORY=git://github.com/commontk/DCMTK.git
Slicer_DCMTK_GIT_TAG=patched-DCMTK-3.6.6_20210115
Slicer_ITK_GIT_REPOSITORY=git://github.com/InsightSoftwareConsortium/ITK
Slicer_ITK_GIT_TAG=2b34388159c20c0a6334d9b174fc6c230853988c
Slicer_CTK_GIT_REPOSITORY=git://github.com/commontk/CTK.git
Slicer_CTK_GIT_TAG=9a9573ec4e0653ee96fe02823ac7ee66b40d3b44
Slicer_LibArchive_GIT_REPOSITORY=git://github.com/libarchive/libarchive.git
Slicer_LibArchive_GIT_TAG=34940ef6ea0b21d77cb501d235164ad88f19d40c
Slicer_RapidJSON_GIT_REPOSITORY=git://github.com/miloyip/rapidjson.git
Slicer_RapidJSON_GIT_TAG=v1.1.0
Slicer_SimpleITK_GIT_REPOSITORY=git://github.com/SimpleITK/SimpleITK.git
Slicer_SimpleITK_GIT_TAG=460f9c1553621b649f376bb1c07c94d4bdf6f055
Slicer_JsonCpp_GIT_REPOSITORY=git://github.com/Slicer/jsoncpp.git
Slicer_JsonCpp_GIT_TAG=73b8e172d6615251ef851d883ef02f163e7075b2
Slicer_ParameterSerializer_GIT_REPOSITORY=git://github.com/Slicer/ParameterSerializer.git
Slicer_ParameterSerializer_GIT_TAG=70e95f1cdee52cc49dfc3375e956a8f5958240c7
Slicer_SlicerExecutionModel_GIT_REPOSITORY=git://github.com/Slicer/SlicerExecutionModel.git
Slicer_SlicerExecutionModel_GIT_TAG=f19d6e88a94ba8f31ddafcff4adf185fe90d7e72
Slicer_qRestAPI_GIT_REPOSITORY=git://github.com/commontk/qRestAPI.git
Slicer_qRestAPI_GIT_TAG=ddc0cfcc220d0ccd02b4afdd699d1e780dac3fa3

EOF

#
# List of variable obtained by locally modifying "ExternalProject_SetIfNotDefined"
#
# Patch:
#
# diff --git a/CMake/ExternalProjectDependency.cmake b/CMake/ExternalProjectDependency.cmake
# index 0f775d3ff0..c9a77856de 100644
# --- a/CMake/ExternalProjectDependency.cmake
# +++ b/CMake/ExternalProjectDependency.cmake
# @@ -1055,6 +1055,7 @@ macro(ExternalProject_SetIfNotDefined var defaultvalue)
#      endif()
#      set(${var} "${defaultvalue}")
#    endif()
# +  message(STATUS "${var}=${${var}}")
#  endmacro()
# 
#  #.rst:

# Collect project names
for entry in $(cat "${slicer_git_dependencies_file}" | grep "GIT_REPOSITORY"); do
  proj=$(echo ${entry} | cut -d= -f1 | cut -d_ -f2)
  repo=$(echo ${entry} | cut -d= -f2)
  sha=$(cat "${slicer_git_dependencies_file}" | grep ${proj}_GIT_TAG | cut -d= -f2)
  if [[ ! -d "${SLICER_DEPENDENCIES_DIR}/${proj}" ]]; then
    git clone ${repo} ${proj}
  fi
  (cd ${proj}; git fetch --tags origin; git reset --hard HEAD; git checkout ${sha})
  break
done

# List of options to configure Slicer
for entry in $(cat "${slicer_git_dependencies_file}" | grep "GIT_REPOSITORY"); do
  varname=$(echo ${entry} | cut -d= -f1)
  proj=$(echo ${entry} | cut -d= -f1 | cut -d_ -f2)
  local_path=${SLICER_DEPENDENCIES_DIR}/${proj}
  echo "-D${varname}=file://${local_path}"
done