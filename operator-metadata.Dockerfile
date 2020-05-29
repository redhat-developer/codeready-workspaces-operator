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

FROM ubi8

# not applicable to Che, only needed for CRW
ADD controller-manifests /manifests
ADD build /build
RUN /build/scripts/swap_images.sh /manifests


# to test this container by attaching bash shell, need a non-scratch base like ubi8-minimal
# FROM ubi8-minimal
FROM scratch

COPY --from=0 /manifests /manifests

# append Brew metadata here (it will be appended via https://github.com/redhat-developer/codeready-workspaces-operator/blob/master/operator-metadata.Jenkinsfile)
