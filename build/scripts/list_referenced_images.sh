#!/bin/bash
#
# Copyright (c) 2020 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# List all images referenced in csv.yaml files
#

# Usage (OCP 4.6+): list_referenced_images.sh manifests/ 
set -e
readarray -d '' metas < <(find "$1" -name '*csv.yaml' -print0)
yq -r '..|.image?' "${metas[@]}" | grep -E "quay|registry" | sort | uniq
yq -r '..|.value?' "${metas[@]}" | grep -E "quay|registry" | sort | uniq
