        if [[ ! "${QUIET}" ]]; then echo -n "[WARNING] Could not retrieve digest for '${image}'. Use alt URL: "; fi
        tmpfile=$(mktemp)
        echo ${image} | sed -r \
            `# for plugin & devfile registries, use internal Brew versions` \
            -e "s|registry.redhat.io/codeready-workspaces/(pluginregistry-rhel8:.+)|registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-\\1|g" \
            -e "s|registry.redhat.io/codeready-workspaces/(devfileregistry-rhel8:.+)|registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-\\1|g" \
            `# in all other cases (including operator) use published quay images to compute digests` \
            -e "s|registry.redhat.io/codeready-workspaces/(.+)|quay.io/crw/\\1|g" \
            > ${tmpfile}
        alt_image=$(cat ${tmpfile})
        rm -f ${tmpfile}
        if [[ ! "${QUIET}" ]]; then echo "${alt_image}"; fi

        digest="$(skopeo inspect --tls-verify=false docker://${alt_image} | jq -r '.Digest')"
        if [[ ! "${QUIET}" ]]; then echo -n "[INFO] Got digest"; fi
        echo "    $digest # ${alt_image}"
        if [[ ! ${digest} ]]; then
          echo "[ERROR] Could not retrieve digest for '${image}' or '${alt_image}': fail!"; exit 1
        fi
