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
# convert che-operator olm files (csv, crd) to downstream using transforms

set -e
SCRIPTS_DIR=$(cd "$(dirname "$0")"; pwd)

# defaults
CSV_VERSION=2.3.0
CRW_TAG=${CSV_VERSION%.*}
CSV_VERSION_PREV=2.2.0

usage () {
	echo "Usage:   $0 -v [CRW CSV_VERSION] -p [CRW CSV_VERSION_PREV] -s [/path/to/sources] -t [/path/to/generated] [--che che.csv.version]"
	echo "Example: $0 -v 2.3.0 -p 2.2.0 -s ${HOME}/projects/che-operator -t `pwd` --che 9.9.9-nightly.1594657566"
	echo "Example: $0 -v 2.3.0 -p 2.2.0 -s ${HOME}/projects/che-operator -t `pwd` [if no che.version, use value in codeready-workspaces/master/pom.xml]"
}

if [[ $# -lt 8 ]]; then usage; exit; fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '--che') CHE_VERSION="$2"; shift 1;;
	# for CSV_VERSION = 2.2.0, get CRW_TAG = 2.2
	'-v') CSV_VERSION="$2"; CRW_TAG="${CSV_VERSION%.*}"; shift 1;;
	# previous version to set in CSV
	'-p') CSV_VERSION_PREV="$2"; shift 1;;
	# paths to use for input and ouput
	'-s') SOURCEDIR="$2"; SOURCEDIR="${SOURCEDIR%/}"; shift 1;;
	'-t') TARGETDIR="$2"; TARGETDIR="${TARGETDIR%/}"; shift 1;;
	'--help'|'-h') usage; exit;;
	# optional tag overrides
	'--crw-tag') CRW_TAG="$2"; shift 1;;
  esac
  shift 1
done

# get che version from crw server root pom, eg., 7.14.3
if [[ ! ${CHE_VERSION} ]]; then
  CHE_VERSION="$(curl -sSLo - https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/master/pom.xml | grep -E "<che.version>" | sed -r -e "s#.+<che.version>(.+)</che.version>#\1#" || exit 1)"
fi

pushd "${SOURCEDIR}" >/dev/null || exit

# Copy digests scripts
for d in addDigests.sh buildDigestMap.sh digestExcludeList images.sh olm.sh; do rsync -zrltq "${SOURCEDIR}/olm/${d}" "${SCRIPTS_DIR}"; done
# Fix "help" messages for digest scripts
sed -r \
	-e 's|("Example:).*"|\1 $0 -w $(pwd) -s manifests -r \\".*.csv.yaml\\" -t '${CRW_TAG}'"|g' \
	-i "${SCRIPTS_DIR}/addDigests.sh"
sed -r \
	-e 's|("Example:).*"|\1 $0 -w $(pwd) -c $(pwd)/manifests/codeready-workspaces.csv.yaml -t '${CRW_TAG}'"|g' \
	-i "${SCRIPTS_DIR}/buildDigestMap.sh"

# simple copy
mkdir -p ${TARGETDIR}/deploy/crds ${TARGETDIR}/manifests/
for CRDFILE in \
	"${TARGETDIR}/manifests/codeready-workspaces.crd.yaml" \
	"${TARGETDIR}/deploy/crds/org_v1_che_crd.yaml"; do
	cp "${SOURCEDIR}"/olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/"${CHE_VERSION}"/*crd.yaml "${CRDFILE}"
done

ICON="$(cat "${SCRIPTS_DIR}/sync-che-olm-to-crw-olm.icon.txt")"
for CSVFILE in \
	${TARGETDIR}/manifests/codeready-workspaces.csv.yaml; do
	cp olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/"${CHE_VERSION}"/*clusterserviceversion.yaml "${CSVFILE}"
	# transform resulting file
	NOW="$(date -u +%FT%T+00:00)"
	sed -r \
		-e 's|certified: "false"|certified: "true"|g' \
		-e "s|https://github.com/eclipse/che-operator|https://github.com/redhat-developer/codeready-workspaces-operator/|g" \
		-e "s|url: https*://www.eclipse.org/che/docs|url: https://access.redhat.com/documentation/en-us/red_hat_codeready_workspaces|g" \
		-e "s|url: https*://www.eclipse.org/che|url: https://developers.redhat.com/products/codeready-workspaces/overview/|g" \
		\
		-e 's|"eclipse-che"|"codeready-workspaces"|g' \
		-e 's|che-operator|codeready-operator|g' \
		-e "s|Eclipse Che|CodeReady Workspaces|g" \
		-e "s|Eclipse Foundation|Red Hat, Inc.|g" \
		\
		-e "s|name: .+preview-openshift.v${CHE_VERSION}|name: crwoperator.v${CSV_VERSION}|g" \
		\
		-e 's|Keycloak|Red Hat SSO|g' \
		-e 's|my-keycloak|my-rhsso|' \
		\
		-e "s|    - base64data: .+|${ICON}|" \
		-e "s|createdAt:.+|createdAt: \"${NOW}\"|" \
		\
		-e 's|email: dfestal@redhat.com|email: nboldt@redhat.com|' \
		-e 's|name: David Festal|name: Nick Boldt|' \
		-e 's@((name|support): Red Hat), Inc.@\1@g' \
		\
		-e 's|/usr/local/bin/codeready-operator|/usr/local/bin/che-operator|' \
		-e 's|imagePullPolicy: IfNotPresent|imagePullPolicy: Always|' \
		-e "s|replaces: eclipse-che-preview-openshift.v.+|replaces: crwoperator.v${CSV_VERSION_PREV}|" \
		-e "s|version: ${CHE_VERSION}|version: ${CSV_VERSION}|g" \
		\
		-e 's|"cheImageTag": "nightly"|"cheImageTag": ""|' \
		-e 's|"devfileRegistryImage":.".+"|"devfileRegistryImage": ""|' \
		-e 's|"pluginRegistryImage":.".+"|"pluginRegistryImage": ""|' \
		-e 's|"identityProviderImage":.".+"|"identityProviderImage": ""|' \
		\
		-e "s|quay.io/eclipse/codeready-operator:${CHE_VERSION}|registry.redhat.io/codeready-workspaces/crw-2-rhel8-operator:${CRW_TAG}|" \
		-e "s|quay.io/eclipse/che-server:.+|registry.redhat.io/codeready-workspaces/server-rhel8:${CRW_TAG}|" \
		-e "s|quay.io/eclipse/che-plugin-registry:.+|registry.redhat.io/codeready-workspaces/pluginregistry-rhel8:${CRW_TAG}|" \
		-e "s|quay.io/eclipse/che-devfile-registry:.+|registry.redhat.io/codeready-workspaces/devfileregistry-rhel8:${CRW_TAG}|" \
		-e "s|quay.io/eclipse/che-plugin-metadata-broker:.+|registry.redhat.io/codeready-workspaces/pluginbroker-metadata-rhel8:${CRW_TAG}|" \
		-e "s|quay.io/eclipse/che-plugin-artifacts-broker:.+|registry.redhat.io/codeready-workspaces/pluginbroker-artifacts-rhel8:${CRW_TAG}|" \
		-e "s|quay.io/eclipse/che-jwtproxy:.+|registry.redhat.io/codeready-workspaces/jwtproxy-rhel8:${CRW_TAG}|" \
		\
		-e "s|registry.access.redhat.com/ubi8-minimal:.+|registry.access.redhat.com/ubi8-minimal:8.2|" \
		-e "s|centos/postgresql-96-centos7:9.6|registry.redhat.io/rhel8/postgresql-96:1|" \
		-e "s|quay.io/eclipse/che-keycloak:.+|registry.redhat.io/rh-sso-7/sso74-openshift-rhel8:7.4|" \
		-e "s|quay.io/eclipse/codeready-operator:nightly|registry.redhat.io/codeready-workspaces/crw-2-rhel8-operator:${CRW_TAG}|" \
		-e "s|quay.io/eclipse/codeready-operator:${CHE_VERSION}|registry.redhat.io/codeready-workspaces/crw-2-rhel8-operator:${CRW_TAG}|" \
		-e 's|IMAGE_default_|RELATED_IMAGE_|' \
		\
		` # TODO is this the correct value to set here?` \
		-e 's|operatorframework.io/suggested-namespace: .+|operatorframework.io/suggested-namespace: workspaces|' \
		-i "${CSVFILE}"
	# insert missing cheFlavor annotation
	if [[ ! $(grep -E '"cheFlavor":"codeready",' "${CSVFILE}") ]]; then 
		sed -r '/.*"cheImageTag": ".*",/a \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ "cheFlavor": "codeready",' \
			-i "${CSVFILE}"
	fi
	if [[ $(diff -u "${SOURCEDIR}/olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/${CHE_VERSION}"/*clusterserviceversion.yaml "${CSVFILE}") ]]; then
		echo "Converted (sed) ${CSVFILE}"
	fi

	# yq changes - transform env vars from Che to CRW values
	changed="$(cat "${CSVFILE}" | yq  -Y '.spec.displayName="Red Hat CodeReady Workspaces"')" && \
		echo "${changed}" > "${CSVFILE}"
	if [[ $(diff -u "${SOURCEDIR}/olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/${CHE_VERSION}"/*clusterserviceversion.yaml "${CSVFILE}") ]]; then
		echo "Converted (yq #1) ${CSVFILE}:"
		for updateName in ".spec.displayName"; do 
			echo -n " * $updateName: "
			cat  "${CSVFILE}" | yq "${updateName}" 2>/dev/null
		done
	fi

	# yq changes - transform env vars from Che to CRW values
	declare -A operator_replacements=(
		["CHE_VERSION"]="${CSV_VERSION}" # set this to x.y.z version, matching the CSV
		["CHE_FLAVOR"]="codeready"
		["CONSOLE_LINK_NAME"]="che" # use che, not workspaces - CRW-1078
	)
	for updateName in "${!operator_replacements[@]}"; do
# 		# .spec.install.spec.deployments[].spec.template.spec.containers[].env[].CHE_VERSION
 		changed="$(cat "${CSVFILE}" | yq  -Y --arg updateName "${updateName}" --arg updateVal "${operator_replacements[$updateName]}" \
		 	'.spec.install.spec.deployments[].spec.template.spec.containers[].env = [.spec.install.spec.deployments[].spec.template.spec.containers[].env[] | if (.name == $updateName) then (.value = $updateVal) else . end]')" && \
 		echo "${changed}" > "${CSVFILE}"
	done

	# add more RELATED_IMAGE_ fields for the images referenced by the registries
	${SCRIPTS_DIR}/insert-related-images-to-csv.sh -v ${CSV_VERSION} -t ${TARGETDIR}

	if [[ $(diff -q -u "${SOURCEDIR}/olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/${CHE_VERSION}"/*clusterserviceversion.yaml "${CSVFILE}") ]]; then
		echo "Converted + inserted (yq #2) ${CSVFILE}:"
		for updateName in "${!operator_replacements[@]}"; do 
			echo -n " * $updateName: "
			cat  "${CSVFILE}" | yq --arg updateName "${updateName}" '.spec.install.spec.deployments[].spec.template.spec.containers[].env? | .[] | select(.name == $updateName) | .value' 2>/dev/null
		done
	fi
done

popd >/dev/null || exit

