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

# https://access.redhat.com/containers/?tab=tags#/registry.access.redhat.com/ubi8-minimal
FROM registry.access.redhat.com/ubi8-minimal:8.2-345 as builder
RUN microdnf install -y findutils

# not applicable to Che, only needed for CRW
ADD manifests /manifests
ADD build /build
RUN /build/scripts/swap_images.sh /manifests

FROM scratch
COPY --from=builder /manifests /manifests

# append Brew metadata here (it will be appended via https://github.com/redhat-developer/codeready-workspaces-operator/blob/master/operator-metadata.Jenkinsfile)
