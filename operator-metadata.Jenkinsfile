#!/usr/bin/env groovy

import groovy.transform.Field

// PARAMETERS for this pipeline:
// FORCE_BUILD = "false"

@Field String SOURCE_BRANCH = "7.20.x" // branch of source repo from which to find and sync commits to pkgs.devel repo
@Field String CSV_VERSION_PREV = "2.4.0"
@Field String MIDSTM_BRANCH = "crw-2.5-rhel-8" // target branch in GH repo, eg., crw-2.5-rhel-8

def SOURCE_REPO = "eclipse/che-operator" //source repo from which to find and sync commits to pkgs.devel repo
def MIDSTM_REPO = "redhat-developer/codeready-workspaces-operator" //source repo from which to find and sync commits to pkgs.devel repo
def DWNSTM_REPO = "containers/codeready-workspaces-operator-metadata" // dist-git repo to use as target
def DWNSTM_BRANCH = MIDSTM_BRANCH // target branch in dist-git repo, eg., crw-2.5-rhel-8
def SCRATCH = "false"
def PUSH_TO_QUAY = "true"
def QUAY_PROJECT = "operator-metadata" // also used for the Brew dockerfile params
def OLD_SHA_DWN=""

def buildNode = "rhel7-releng" // slave label
timeout(120) {
	node("${buildNode}"){ stage "Sync repos"
      sh('curl -sSLO https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/'+ DWNSTM_BRANCH + '/product/util.groovy')
      def util = load "${WORKSPACE}/util.groovy"
      cleanWs()
      CRW_VERSION = util.getCrwVersion(MIDSTM_BRANCH)
      println "CRW_VERSION = '" + CRW_VERSION + "'"
      util.installSkopeo(CRW_VERSION)
      until.installYq()
      CSV_VERSION = util.getCSVVersion(MIDSTM_BRANCH)
      println "CSV_VERSION = '" + CSV_VERSION + "'"
      withCredentials([string(credentialsId:'devstudio-release.token', variable: 'GITHUB_TOKEN'), 
        file(credentialsId: 'crw-build.keytab', variable: 'CRW_KEYTAB')]) {
          util.bootstrap(CRW_KEYTAB)

          util.cloneRepo("https://github.com/${SOURCE_REPO}.git", "${WORKSPACE}/sources", SOURCE_BRANCH)
          SOURCE_SHA = util.getLastCommitSHA("${WORKSPACE}/sources")
          println "Got SOURCE_SHA in sources folder: " + SOURCE_SHA

          util.cloneRepo("https://github.com/${MIDSTM_REPO}.git", "${WORKSPACE}/targetmid", MIDSTM_BRANCH)
          MIDSTM_SHA = util.getLastCommitSHA("${WORKSPACE}/targetmid")
          println "Got MIDSTM_SHA in targetmid folder: " + MIDSTM_SHA

          def BOOTSTRAP = '''#!/bin/bash -xe
hasChanged=0

# REQUIRE: skopeo
curl -L -s -S https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/''' + MIDSTM_BRANCH + '''/product/updateBaseImages.sh -o /tmp/updateBaseImages.sh
chmod +x /tmp/updateBaseImages.sh


# fetch sources to be updated
DWNSTM_REPO="''' + DWNSTM_REPO + '''"
if [[ ! -d ${WORKSPACE}/targetdwn ]]; then git clone ssh://crw-build@pkgs.devel.redhat.com/${DWNSTM_REPO} targetdwn; fi
  cd ${WORKSPACE}/targetdwn
  git checkout --track origin/''' + DWNSTM_BRANCH + ''' || true
  git config user.email crw-build@REDHAT.COM
  git config user.name "CRW Build"
  git config --global push.default matching
cd ..

'''
              sshagent(credentials : ['devstudio-release'])
              {
                // UP2MID are right now ONLY files in olm/ folder upstream copied to build/scripts/ folder midstream
                // TODO add in addDigests.sh buildDigestMap.sh from upstream (which are very different from downsteam versions)
                def SYNC_FILES_UP2MID = "digestExcludeList images.sh olm.sh" 

                sh BOOTSTRAP + '''

# rsync files in upstream github to dist-git
for d in ''' + SYNC_FILES_UP2MID + '''; do
  if [[ -f ${WORKSPACE}/sources/olm/${d} ]]; then
    rsync -zrlt ${WORKSPACE}/sources/olm/${d} ${WORKSPACE}/targetmid/build/scripts/${d}
  elif [[ -d ${WORKSPACE}/sources/olm/${d} ]]; then
    # copy over the files
    rsync -zrlt ${WORKSPACE}/sources/olm/${d}/* ${WORKSPACE}/targetmid/build/scripts/${d}/
    # sync the directory and delete from targetmid if deleted from source
    rsync -zrlt --delete ${WORKSPACE}/sources/olm/${d}/ ${WORKSPACE}/targetmid/build/scripts/${d}/
  fi
done

CSV_NAME="codeready-workspaces"
CSV_FILE="\$( { find ${WORKSPACE}/targetdwn/manifests/ -name "${CSV_NAME}.csv.yaml" | tail -1; } || true)"; 
echo "[INFO] CSV_FILE = ${CSV_FILE}"
# if [[ ! ${CSV_FILE} ]]; then 
  # CRW-878 generate CSV and update CRD from upstream
  cd ${WORKSPACE}/targetmid/build/scripts
  ./sync-che-olm-to-crw-olm.sh -v ''' + CSV_VERSION + ''' -p ''' + CSV_VERSION_PREV + ''' -s ${WORKSPACE}/sources -t ${WORKSPACE}/targetmid --crw-branch ''' + MIDSTM_BRANCH + '''
  cd ${WORKSPACE}/targetmid/
  # if anything has changed other than the createdAt date, then we commit this
  if [[ $(git diff | grep -v createdAt | egrep "^(-|\\+) ") ]]; then
    git add . -A -f
    git commit -s -m "[csv] Add CSV ''' + CSV_VERSION + '''" .
    git push origin ''' + MIDSTM_BRANCH + '''
  else # no need to push this so revert
    echo "[INFO] No significant changes (other than createdAt date) so revert and do not commit"
    git checkout manifests/ build/scripts/
  fi
# fi
'''

                util.updateBaseImages("${WORKSPACE}/targetmid", MIDSTM_BRANCH, "-f operator-metadata.Dockerfile -maxdepth 1")

              }

          def SYNC_FILES_MID2DWN = "manifests metadata build" // folders in mid/dwn

          OLD_SHA_DWN = util.getLastCommitSHA("${WORKSPACE}/targetdwn")
          println "Got OLD_SHA_DWN in targetdwn folder: " + OLD_SHA_DWN

          sh BOOTSTRAP + '''
# rsync files in github midstream to dist-git downstream
# TODO CRW 2.5 / OCP 4.6 switch to use manifests metadata folders
for d in ''' + SYNC_FILES_MID2DWN + '''; do
  if [[ -f ${WORKSPACE}/targetmid/${d} ]]; then
    rsync -zrlt ${WORKSPACE}/targetmid/${d} ${WORKSPACE}/targetdwn/${d}
  elif [[ -d ${WORKSPACE}/targetmid/${d} ]]; then
    # copy over the files
    rsync -zrlt ${WORKSPACE}/targetmid/${d}/* ${WORKSPACE}/targetdwn/${d}/
    # sync the directory and delete from targetdwn if deleted from targetmid
    rsync -zrlt --delete ${WORKSPACE}/targetmid/${d}/ ${WORKSPACE}/targetdwn/${d}/
  fi
done

cp -f ${WORKSPACE}/targetmid/operator-metadata.Dockerfile ${WORKSPACE}/targetdwn/Dockerfile

CRW_VERSION="''' + CRW_VERSION_F + '''"
#apply patches
sed -i ${WORKSPACE}/targetdwn/Dockerfile \
  -e "s#FROM registry.redhat.io/#FROM #g" \
  -e "s#FROM registry.access.redhat.com/#FROM #g" \
  -e "s/# *RUN yum /RUN yum /g" \

# generate digests from tags
# 1. convert csv to use brew container refs so we can resolve stuff
CSV_NAME="codeready-workspaces"
CSV_FILE="\$(find ${WORKSPACE}/targetdwn/manifests/ -name "${CSV_NAME}.csv.yaml" | tail -1)"; # echo "[INFO] CSV = ${CSV_FILE}"
sed -r \
    `# for plugin & devfile registries, use internal Brew versions` \
    -e "s|registry.redhat.io/codeready-workspaces/(pluginregistry-rhel8:.+)|registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-\\1|g" \
    -e "s|registry.redhat.io/codeready-workspaces/(devfileregistry-rhel8:.+)|registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-\\1|g" \
    -i "${CSV_FILE}"

# 2. generation of digests already done as part of sync-che-olm-to-crw-olm.sh above

# 3. revert to OSBS image refs, since digest pinning will automatically switch them to RHCC values
sed -r \
    -e "s#(quay.io/crw/|registry.redhat.io/codeready-workspaces/)#registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-#g" \
    -i "${CSV_FILE}"
METADATA='ENV SUMMARY="Red Hat CodeReady Workspaces ''' + QUAY_PROJECT + ''' container" \\\r
    DESCRIPTION="Red Hat CodeReady Workspaces ''' + QUAY_PROJECT + ''' container" \\\r
    PRODNAME="codeready-workspaces" \\\r
    COMPNAME="''' + QUAY_PROJECT + '''" \r
LABEL operators.operatorframework.io.bundle.mediatype.v1=registry+v1 \\\r
      operators.operatorframework.io.bundle.manifests.v1=manifests/ \\\r
      operators.operatorframework.io.bundle.metadata.v1=metadata/ \\\r
      operators.operatorframework.io.bundle.package.v1=codeready-workspaces \\\r
      operators.operatorframework.io.bundle.channels.v1=latest \\\r
      operators.operatorframework.io.bundle.channel.default.v1=latest \\\r
      com.redhat.delivery.operator.bundle="true" \\\r
      com.redhat.openshift.versions="v4.5,v4.6" \\\r
      com.redhat.delivery.backport=true \\\r
      summary="$SUMMARY" \\\r
      description="$DESCRIPTION" \\\r
      io.k8s.description="$DESCRIPTION" \\\r
      io.k8s.display-name=\"$DESCRIPTION" \\\r
      io.openshift.tags="$PRODNAME,$COMPNAME" \\\r
      com.redhat.component="$PRODNAME-rhel8-$COMPNAME-container" \\\r
      name="$PRODNAME/$COMPNAME" \\\r
      version="'$CRW_VERSION'" \\\r
      license="EPLv2" \\\r
      maintainer="Nick Boldt <nboldt@redhat.com>, Dmytro Nochevnov <dnochevn@redhat.com>" \\\r
      io.openshift.expose-services="" \\\r
      usage="" \r'

echo -e "$METADATA" >> ${WORKSPACE}/targetdwn/Dockerfile

# push changes in github to dist-git
cd ${WORKSPACE}/targetdwn
if [[ \$(git diff --name-only) ]]; then # file changed
	OLD_SHA_DWN=\$(git rev-parse HEAD) # echo ${OLD_SHA_DWN:0:8}
	git add Dockerfile ''' + SYNC_FILES_MID2DWN + '''
    /tmp/updateBaseImages.sh -b ''' + DWNSTM_BRANCH + ''' --nocommit
  git commit -s -m "[sync] Update from ''' + SOURCE_REPO + ''' @ ''' + SOURCE_SHA + ''' ''' + MIDSTM_REPO + ''' @ ''' + MIDSTM_SHA + '''" \
    Dockerfile ''' + SYNC_FILES_MID2DWN + ''' || true
	git push origin ''' + DWNSTM_BRANCH + '''
	NEW_SHA_DWN=\$(git rev-parse HEAD) # echo ${NEW_SHA_DWN:0:8}
	if [[ "${OLD_SHA_DWN}" != "${NEW_SHA_DWN}" ]]; then hasChanged=1; fi
  echo "[sync] Updated pkgs.devel @ ${NEW_SHA_DWN:0:8} from ''' + SOURCE_REPO + ''' @ ''' + SOURCE_SHA + ''' ''' + MIDSTM_REPO + ''' @ ''' + MIDSTM_SHA + '''"
else
    # file not changed, but check if base image needs an update
    # (this avoids having 2 commits for every change)
    cd ${WORKSPACE}/targetdwn
    OLD_SHA_DWN=\$(git rev-parse HEAD) # echo ${OLD_SHA_DWN:0:8}
    /tmp/updateBaseImages.sh -b ''' + DWNSTM_BRANCH + '''
    NEW_SHA_DWN=\$(git rev-parse HEAD) # echo ${NEW_SHA_DWN:0:8}
    if [[ "${OLD_SHA_DWN}" != "${NEW_SHA_DWN}" ]]; then hasChanged=1; fi
    cd ..
fi
cd ..

# NOTE: this image needs to build in Brew (CRW <=2.3), then rebuild for Quay, so use QUAY_REBUILD_PATH instead of QUAY_REPO_PATHs variable
# For CRW 2.4, do not rebuild (just copy to Quay) and use an ImageContentSourcePolicy file to resolve images
# https://gitlab.cee.redhat.com/codeready-workspaces/knowledge-base/-/blob/master/installStagingCRW.md#create-imagecontentsourcepolicy
if [[ ''' + FORCE_BUILD + ''' == "true" ]]; then hasChanged=1; fi
if [[ ${hasChanged} -eq 1 ]]; then
  for QRP in ''' + QUAY_PROJECT + '''; do
    # do NOT append -rhel8 suffix here: metadata image is os-agnostic
    QUAY_REPO_PATH=""; if [[ ''' + PUSH_TO_QUAY + ''' == "true" ]]; then QUAY_REPO_PATH="crw-2-rhel8-${QRP}"; fi
    curl \
"https://codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com/job/get-sources-rhpkg-container-build/buildWithParameters?\
token=CI_BUILD&\
cause=${QUAY_REPO_PATH}+respin+by+${BUILD_TAG}&\
GIT_BRANCH=''' + DWNSTM_BRANCH + '''&\
GIT_PATHs=containers/codeready-workspaces-${QRP}&\
QUAY_REPO_PATHs=${QUAY_REPO_PATH}&\
JOB_BRANCH=${CRW_VERSION}&\
FORCE_BUILD=true&\
SCRATCH=''' + SCRATCH + '''"
  done
fi

if [[ ${hasChanged} -eq 0 ]]; then
  echo "No changes upstream, nothing to commit"
fi
'''
        }

          def NEW_SHA_DWN = util.getLastCommitSHA("${WORKSPACE}/targetdwn")
	        println "Got NEW_SHA_DWN in targetdwn folder: " + NEW_SHA_DWN

	        if (NEW_SHA_DWN.equals(OLD_SHA_DWN)) {
	          currentBuild.result='UNSTABLE'
	        }
	}
}
