#!/bin/bash
#
# Copyright (c) 2021-2022 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation
#
# convert che-server upstream to devspaces-server tarball downstream using sed

set -e

SCRIPTS_DIR=$(cd "$(dirname "$0")"; pwd)

# defaults
CSV_VERSION=3.y.0 # csv 3.y.0
DS_VERSION=${CSV_VERSION%.*} # tag 3.y

usage () {
    echo "
Usage:   $0 -v [DS CSV_VERSION] [-s /path/to/che-server] [-t /path/to/generated]
Example: $0 -v 3.y.0 -s ${HOME}/projects/che -t /tmp/ds-server"
    exit
}

if [[ $# -lt 6 ]]; then usage; fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
    # for CSV_VERSION = 2.2.0, get DS_VERSION = 2.2
    '-v') CSV_VERSION="$2"; DS_VERSION="${CSV_VERSION%.*}"; shift 1;;
    # paths to use for input and ouput
    '-s') SOURCEDIR="$2"; SOURCEDIR="${SOURCEDIR%/}"; shift 1;;
    '-t') TARGETDIR="$2"; TARGETDIR="${TARGETDIR%/}"; shift 1;;
    '--help'|'-h') usage;;
  esac
  shift 1
done

if [[ ! -d "${SOURCEDIR}" ]]; then usage; fi
if [[ ! -d "${TARGETDIR}" ]]; then usage; fi
if [[ "${CSV_VERSION}" == "3.y.0" ]]; then usage; fi

# global / generic changes
echo ".github/
.git/
.gitattributes
dockerfiles/
assets/branding/
build/scripts/sync.sh
build/dockerfiles
/container.yaml
/content_sets.*
/cvp.yml
/cvp-owners.yml
/fetch-artifacts-pnc.yaml
get-source*.sh
tests/basic-test.yaml
.ci
.dependabot
.repositories-update-contributing.sh
.repositories.yaml
/CHANGELOG.md
/CODE_OF_CONDUCT.md
/CONTRIBUTING.md
/Dockerfile
/LICENSE
/NUMBERING.md
/README.md
/RELEASE.md
/devfile.yaml
/make-release.sh
/README.adoc
" > /tmp/rsync-excludes
echo "Rsync ${SOURCEDIR} to ${TARGETDIR}"
rsync -azrlt --checksum --exclude-from /tmp/rsync-excludes --delete ${SOURCEDIR}/ ${TARGETDIR}/
rm -f /tmp/rsync-excludes

# copy entrypoint.sh
rsync -azrlt --checksum ${SOURCEDIR}/build/dockerfiles/entrypoint.sh ${TARGETDIR}

# ensure shell scripts are executable
find ${TARGETDIR}/ -name "*.sh" -exec chmod +x {} \;

pnc_build_id=""

# pnc methods require properly configured ~/.config/pnc-bacon/config.yaml w/ username + clientSecret set
getPNCIDs () {
    SOURCE_BRANCH=$(cd $SOURCEDIR; git branch --show-current)

    # 0. compute buildConfig ID, eg., main => 8937 or 7.56.x => 8936; also compute pnc_project_id = 1274
    pnc_buildconfig_id=$(pnc build-config list --query "project.name==devspaces-server;scmRevision==${SOURCE_BRANCH}" | yq -r '.[].id')
    if [[ ! $pnc_buildconfig_id ]]; then 
        echo "[ERROR] Could not find a build-config for pnc build-config list --query \"project.name==devspaces-server;scmRevision==${SOURCE_BRANCH}\" | yq -r '.[].id'"
        echo "[ERROR] Please check your build-configs at https://orch.psi.redhat.com/pnc-web/#/projects/1274 - maybe something is misconfigured?"
        exit 2
    else
        echo "[INFO] Found build-config for scmRevision ${SOURCE_BRANCH}: $pnc_buildconfig_id"
    fi
    pnc_project_id=$(pnc build-config list --query "project.name==devspaces-server;scmRevision==${SOURCE_BRANCH}" | yq -r '.[].project.id')
}

getLastPNCBuild () {
    # 1a. use latest build
    echo "[INFO] Using latest PNC build for project.name==devspaces-server;scmRevision==${SOURCE_BRANCH} (pnc_buildconfig_id=$pnc_buildconfig_id, pnc_project_id=$pnc_project_id) ..."
    pnc_build_id=$(pnc build-config list-builds ${pnc_buildconfig_id} --latest | yq -r '.[].id')
    echo "[INFO] Latest PNC build ID: ${pnc_build_id}"
}

triggerPNCBuild () {
    # 1b. run a new build, ~5-6mins
    echo "[INFO] Start a new PNC build for project.name==devspaces-server;scmRevision==${SOURCE_BRANCH} (pnc_buildconfig_id=$pnc_buildconfig_id, pnc_project_id=$pnc_project_id) ..."
    echo "[INFO] See build in progress (~6mins) at:"
    echo "[INFO] https://orch.psi.redhat.com/pnc-web/#/projects/${pnc_project_id}/build-configs/${pnc_buildconfig_id}"

    logfile=$(mktemp)
    pnc build start --rebuild-mode=FORCE --wait ${pnc_buildconfig_id} | tee ${logfile}
    # running builds can be seen from https://orch.psi.redhat.com/pnc-web/#/projects/1274

    # 2. find the build ID for the completed build, eg., AVN43G4HK3YAA
    pnc_build_id=$(cat ${logfile} | yq -r '.id' || echo "")
    echo "[INFO] New PNC build ID: ${pnc_build_id}"

    # 3. cleanup
    if [[ $pnc_build_id ]]; then 
        rm -f ${logfile}
    fi
}

# requires pnc_buildconfig_id, pnc_project_id, pnc_build_id
generateFetchArtifactsPNCYaml () {
    if [[ $pnc_build_id ]]; then 
        # 1. use build ID to query for artifact version, eg., 7.58.0.redhat-00004
        pnc_artifact_version=$(pnc build list --query "id==${pnc_build_id}" | yq -r '.[].attributes.BREW_BUILD_VERSION')

        # 2. use artifact version to query for artifact ID, eg., 9401563
        pnc_artifact_id=$(pnc build list-built-artifacts "${pnc_build_id}" --query "identifier==org.eclipse.che:assembly-main:tar.gz:${pnc_artifact_version}" | yq -r '.[].id')

        # 3. generate new fetch-artifacts-pnc.yaml file
        echo "builds:
  # https://orch.psi.redhat.com/pnc-web/#/projects/${pnc_project_id}/build-configs/${pnc_buildconfig_id}/builds/${pnc_build_id}
  # build id must be string
  - build_id: '${pnc_build_id}'
    artifacts:
      # https://orch.psi.redhat.com/pnc-web/#/artifacts/${pnc_artifact_id}
      # ==> org.eclipse.che:assembly-main:tar.gz:${pnc_artifact_version}
      # artifact id must be string; rename it by setting a different target path/file
      - id: '${pnc_artifact_id}'
        target: assembly-main.tar.gz
" > ${TARGETDIR}/fetch-artifacts-pnc.yaml
        echo "Updated fetch-artifacts-pnc.yaml with build $pnc_build_id and artifact pnc_artifact_id"
    else
        echo "No change to fetch-artifacts-pnc.yaml"
    fi
}

getPNCIDs
if [[ $(cd ${TARGETDIR}; git status -s || true) ]]; then # dirty workspace, something changed upstream, need a new build
    triggerPNCBuild
else
    getLastPNCBuild
fi
generateFetchArtifactsPNCYaml

sed_in_place() {
    SHORT_UNAME=$(uname -s)
  if [ "$(uname)" == "Darwin" ]; then
    sed -i '' "$@"
  elif [ "${SHORT_UNAME:0:5}" == "Linux" ]; then
    sed -i "$@"
  fi
}

sed_in_place -r \
  `# Update DevSpaces version for Dockerfile` \
  -e "s/version=.*/version=\"$DS_VERSION\" \\\/" \
  -e "s/pnc_artifact_id=.*/pnc_artifact_id=\"$pnc_artifact_id\" \\\/" \
  -e "s/pnc_build_id=.*/pnc_build_id=\"$pnc_build_id\" \\\/" \
  "${TARGETDIR}"/build/dockerfiles/brew.Dockerfile

echo "Converted Dockerfile"

# add ignore for the tarball in mid and downstream
echo "/assembly-main.tar.gz" >> ${TARGETDIR}/.gitignore
echo "Adjusted .gitignore"
