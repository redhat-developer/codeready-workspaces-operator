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
CRW_VERSION=2.2.0
CRW_TAG=${CRW_VERSION%.*}
CRW_VERSION_PREV=2.1.1

usage () {
	echo "Usage:   $0 -v [VERSION] [-p PREV_VERSION] [-s /path/to/sources] [-t /path/to/generated]"
	echo "Example: $0 -v 2.2.0 -p 2.1.1 -s ${HOME}/projects/che-operator -t /tmp/crw-operator"
}

if [[ $# -lt 8 ]]; then usage; exit; fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
	# for CRW_VERSION = 2.2.0, get CRW_TAG = 2.2
	'-v') CRW_VERSION="$1"; CRW_TAG="${CRW_VERSION%.*}" shift 1;;
	# previous version to set in CSV
	'-p') CRW_VERSION_PREV="$1"; shift 1;;
	# paths to use for input and ouput
	'-s') SOURCEDIR="$1"; SOURCEDIR="${SOURCEDIR%/}"; shit 1;;
	'-t') TARGETDIR="$2"; TARGETDIR="${TARGETDIR%/}"; shit 1;;
	'--help'|'-h') usage; exit;;
	# optional tag overrides
	'--crw-tag') CRW_TAG="$1"; shift 1;;
  esac
  shift 1
done

# get che version from crw server root pom, eg., 7.14.3
CHE_VERSION="$(curl -sSLo - https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/master/pom.xml | grep -E "<che.version>" | sed -r -e "s#.+<che.version>(.+)</che.version>#\1#" || exit 1)"

pushd "${SOURCEDIR}" >/dev/null || exit

# Copy digests scripts
cp "${SOURCEDIR}/olm/addDigests.sh" "${SOURCEDIR}/olm/images.sh" "${SOURCEDIR}/olm/buildDigestMap.sh" "${SCRIPTS_DIR}"
# Fix "help" messages for digest scripts
sed -r \
	-e 's|("Example:).*"|\1 $0 -w $(pwd) -s controller-manifests/v'${CRW_VERSION}' -r \\".*.csv.yaml\\" -t '${CRW_TAG}'"|g' \
	-i "${SCRIPTS_DIR}/addDigests.sh"
sed -r \
	-e 's|("Example:).*"|\1 $0 -w $(pwd) -c $(pwd)/controller-manifests/v'${CRW_VERSION}'/codeready-workspaces.csv.yaml -t '${CRW_TAG}'"|g' \
	-i "${SCRIPTS_DIR}/buildDigestMap.sh"

# simple copy
# TODO when we switch to OCP 4.6 format, remove updates to controller-manifests/v${CRW_VERSION} folder
for CRDFILE in \
	"${TARGETDIR}/controller-manifests/v${CRW_VERSION}/codeready-workspaces.crd.yaml" \
	"${TARGETDIR}/manifests/codeready-workspaces.crd.yaml" \
	"${TARGETDIR}/deploy/crds/org_v1_che_crd.yaml"; do
	cp "${SOURCEDIR}"/olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/"${CHE_VERSION}"/*crd.yaml "${CRDFILE}"
done

ICON="$(cat "${TARGETDIR}/build/scripts/sync-che-olm-to-crw-olm.icon.txt")"
# TODO: when we switch to OCP 4.6 format, use CSVFILE="${TARGETDIR}/manifests/codeready-workspaces.csv.yaml"
for CSVFILE in \
	${TARGETDIR}/controller-manifests/v${CRW_VERSION}/codeready-workspaces.csv.yaml; do
	cp olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/"${CHE_VERSION}"/*clusterserviceversion.yaml "${CSVFILE}"
	# transform resulting file
	NOW="$(date -u +%FT%TZ)"
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
		-e "s|name: .+preview-openshift.v${CHE_VERSION}|name: crwoperator.v${CRW_VERSION}|g" \
		\
		-e 's|Keycloak|Red Hat SSO|g' \
		-e 's|my-keycloak|my-rhsso|' \
		\
		-e "s|    - base64data: .+|${ICON}|" \
		-e "s|createdAt:.+|createdAt: \"${NOW}\"|" \
		\
		-e 's|email: dfestal@redhat.com|email: nboldt@redhat.com|' \
		-e 's|name: David Festal|name: Nick Boldt|' \
		-e 's|name: Red Hat, Inc.|name: Red Hat|' \
		\
		-e 's|/usr/local/bin/codeready-operator|/usr/local/bin/che-operator|' \
		-e 's|imagePullPolicy: IfNotPresent|imagePullPolicy: Always|' \
		-e "s|replaces: eclipse-che-preview-openshift.v.+|replaces: crwoperator.v${CRW_VERSION_PREV}|" \
		-e "s|version: ${CHE_VERSION}|version: ${CRW_VERSION}|g" \
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
		-e "s|quay.io/eclipse/codeready-operator:${CHE_VERSION}|registry.redhat.io/codeready-workspaces/crw-2-rhel8-operator:${CRW_TAG}|" \
		-e "s|quay.io/eclipse/codeready-operator:${CHE_VERSION}|registry.redhat.io/codeready-workspaces/crw-2-rhel8-operator:${CRW_TAG}|" \
		-e 's|||' \
		-i "${CSVFILE}"
	if [[ $(diff -u "${SOURCEDIR}/olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/${CHE_VERSION}"/*clusterserviceversion.yaml "${CSVFILE}") ]]; then
		echo "Converted (sed) ${CSVFILE}"
	fi

	# yq changes - transform env vars from Che to CRW values
	changed="$(cat "${CSVFILE}" | \
yq  -Y '.spec.displayName="Red Hat CodeReady Workspaces"')" && \
		echo "${changed}" > "${CSVFILE}"
	if [[ $(diff -u "${SOURCEDIR}/olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/${CHE_VERSION}"/*clusterserviceversion.yaml "${CSVFILE}") ]]; then
		echo "Converted (yq #2) ${CSVFILE}"
	fi

	# yq changes - transform env vars from Che to CRW values
	declare -A operator_replacements=(
		["CHE_VERSION"]="${CRW_VERSION}"
		["CHE_FLAVOR"]="codeready"
		["CONSOLE_LINK_NAME"]="workspaces"
	)
	# TODO make this work!
	# for updateName in "${!operator_replacements[@]}"; do
# 		# .spec.install.spec.deployments[].spec.template.spec.containers.env.CHE_VERSION
# 		changed="$(cat "${CSVFILE}" | \
# yq  -y --arg updateName "${updateName}" --arg updateVal "${operator_replacements[$updateName]}" \
# '.spec.install.spec.deployments[].spec.template.spec.containers[].env = [.spec.install.spec.deployments[].spec.template.spec.containers[].env[] | if (.name == $updateName) then (.value = $updateVal) else . end]' | \
# yq  -y 'del(.spec.template.spec.containers[0].env[] | select(.name == "RELATED_IMAGE_che_tls_secrets_creation_job"))')" && \
# 		echo "${changed}" > "${CSVFILE}"
	# done
# 	if [[ $(diff -u "${SOURCEDIR}/olm/eclipse-che-preview-openshift/deploy/olm-catalog/eclipse-che-preview-openshift/${CHE_VERSION}"/*clusterserviceversion.yaml "${CSVFILE}") ]]; then
# 		echo "Converted (yq #1) ${CSVFILE}"
# 	fi

	# TODO add cheFlavour:codeready into nested yaml in .metadata.annotations[] -- cannot be transformed with yq!

done

popd >/dev/null || exit

