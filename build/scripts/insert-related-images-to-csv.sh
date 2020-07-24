#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation
#
# insert RELATED_IMAGE_ fields for images referenced by the plugin and devfile registries

set -e
SCRIPTS_DIR=$(cd "$(dirname "$0")"; pwd)

# defaults
CSV_VERSION=2.3.0
CRW_TAG=${CSV_VERSION%.*}

# TODO handle cmdline input
usage () {
	echo "Usage:   $0 -v [CRW CSV_VERSION] -t [/path/to/generated]"
	echo "Example: $0 -v 2.3.0 -t `pwd`"
}

if [[ $# -lt 4 ]]; then usage; exit; fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
	# for CSV_VERSION = 2.2.0, get CRW_TAG = 2.2
	'-v') CSV_VERSION="$2"; CRW_TAG="${CSV_VERSION%.*}"; shift 1;;
	'-t') TARGETDIR="$2"; TARGETDIR="${TARGETDIR%/}"; shift 1;;
	'--help'|'-h') usage; exit;;
  esac
  shift 1
done

CONTAINERS=""
tmpdir=$(mktemp -d); mkdir -p $tmpdir; pushd $tmpdir >/dev/null
    # check out crw sources
    git clone -q https://github.com/redhat-developer/codeready-workspaces crw
    # run cd .../dependencies/che-devfile-registry/; ./build/scripts/list_referenced_images.sh devfiles/
    # run cd .../dependencies/che-plugin-registry/; ./build/scripts/list_referenced_images.sh v3/ | grep 2.3
    CONTAINERS="${CONTAINERS} $(cd crw/dependencies/che-devfile-registry; ./build/scripts/list_referenced_images.sh devfiles/)"
    CONTAINERS="${CONTAINERS} $(cd crw/dependencies/che-plugin-registry; ./build/scripts/list_referenced_images.sh v3/ | grep ${CRW_TAG})"
popd >/dev/null
rm -fr $tmpdir

# TODO: preload container list with the operator since no one else refers to it ? Does it need to be the published version or the OSBS internal one?
# CONTAINERS_UNIQ=("registry.redhat.io/codeready-workspaces/crw-2-rhel8-operator:${CRW_TAG}") # or
# CONTAINERS_UNIQ=("registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-operator:${CRW_TAG}")

# add unique containers to array, then sort
CONTAINERS_UNIQ=()
for c in $CONTAINERS; do if [[ ! "${CONTAINERS_UNIQ[@]}" =~ "${c}" ]]; then CONTAINERS_UNIQ+=($c); fi; done
IFS=$'\n' CONTAINERS=($(sort <<<"${CONTAINERS_UNIQ[*]}")); unset IFS

CSVFILE=${TARGETDIR}/manifests/codeready-workspaces.csv.yaml
# echo "[INFO] Found these images to insert:"
for updateVal in "${CONTAINERS[@]}"; do
  updateName=$(echo ${updateVal} | sed -r -e "s#[^/]+/([^/]+)/([^/]+):([0-9.-]+)#RELATED_IMAGE_\1_\2#g" -e "s@-rhel8@@g" | tr "-" "_")
  # echo " - $updateName = $updateVal"
  cat $CSVFILE | yq -Y --arg updateName "${updateName}" --arg updateVal "${updateVal}" \
    '.spec.install.spec.deployments[].spec.template.spec.containers[].env += [{"name": $updateName, "value": $updateVal}]' \
    > ${CSVFILE}.2; mv ${CSVFILE}.2 ${CSVFILE}
done

# replace external crw refs with internal ones
sed -r -i $CSVFILE \
  -e "s@registry.redhat.io/codeready-workspaces/@registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-@g#" \
  -e "s@registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-crw-2-rhel8-operator@registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-operator@g" \
  -e "s@registry.access.redhat.com/ubi8-minimal@registry.redhat.io/ubi8-minimal@g"

# echo list of RELATED_IMAGE_ entries after adding them above
# cat $CSVFILE | grep RELATED_IMAGE_ -A1
