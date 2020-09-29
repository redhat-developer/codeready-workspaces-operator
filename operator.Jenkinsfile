#!/usr/bin/env groovy

// PARAMETERS for this pipeline:
// SOURCE_BRANCH = "7.16.x" or "master" // branch of source repo from which to find and sync commits to pkgs.devel repo
// FORCE_BUILD = "false"

import groovy.transform.Field

def SOURCE_REPO = "eclipse/che-operator" //source repo from which to find and sync commits to pkgs.devel repo

def MIDSTM_REPO = "redhat-developer/codeready-workspaces-operator" // GH repo to use as target for deploy/ folder
def DWNSTM_REPO = "containers/codeready-workspaces-operator" // dist-git repo to use as target for everything

@Field String MIDSTM_BRANCH = "crw-2.5-rhel-8" // target branch in GH repo, eg., crw-2.5-rhel-8
def DWNSTM_BRANCH = "crw-2.5-rhel-8" // target branch in dist-git repo, eg., crw-2.5-rhel-8
def SCRATCH = "false"
def PUSH_TO_QUAY = "true"
def QUAY_PROJECT = "operator" // also used for the Brew dockerfile params

def OLD_SHA_MID=""
def OLD_SHA_DWN=""

@Field String CRW_VERSION_F = ""
def String getCrwVersion(String MIDSTM_BRANCH) {
  if (CRW_VERSION_F.equals("")) {
    CRW_VERSION_F = sh(script: '''#!/bin/bash -xe
    curl -sSLo- https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/''' + MIDSTM_BRANCH + '''/dependencies/VERSION''', returnStdout: true).trim()
  }
  return CRW_VERSION_F
}

def installSkopeo(String CRW_VERSION)
{
sh '''#!/bin/bash -xe
pushd /tmp >/dev/null
# remove any older versions
sudo yum remove -y skopeo || true
# install from @kcrane build
if [[ ! -x /usr/local/bin/skopeo ]]; then
    sudo curl -sSLO "https://codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com/job/crw-deprecated_''' + CRW_VERSION + '''/lastSuccessfulBuild/artifact/codeready-workspaces-deprecated/skopeo/target/skopeo-$(uname -m).tar.gz"
fi
if [[ -f /tmp/skopeo-$(uname -m).tar.gz ]]; then 
    sudo tar xzf /tmp/skopeo-$(uname -m).tar.gz --overwrite -C /usr/local/bin/
    sudo chmod 755 /usr/local/bin/skopeo
    sudo rm -f /tmp/skopeo-$(uname -m).tar.gz
fi
popd >/dev/null
skopeo --version
'''
}

def buildNode = "rhel7-releng" // slave label
timeout(120) {
	node("${buildNode}"){ stage "Sync repos"
    wrap([$class: 'TimestamperBuildWrapper']) {
      cleanWs()
      CRW_VERSION = getCrwVersion(MIDSTM_BRANCH)
      println "CRW_VERSION = '" + CRW_VERSION + "'"
      installSkopeo(CRW_VERSION)
	    withCredentials([string(credentialsId:'devstudio-release.token', variable: 'GITHUB_TOKEN'), 
        file(credentialsId: 'crw-build.keytab', variable: 'CRW_KEYTAB')]) {
          checkout([$class: 'GitSCM',
            branches: [[name: "${SOURCE_BRANCH}"]],
            doGenerateSubmoduleConfigurations: false,
            credentialsId: 'devstudio-release',
            poll: true,
            extensions: [
              [$class: 'RelativeTargetDirectory', relativeTargetDir: "sources"],
            ],
            submoduleCfg: [],
            userRemoteConfigs: [[url: "https://github.com/${SOURCE_REPO}.git"]]])

            def BOOTSTRAP = '''#!/bin/bash -xe

# bootstrapping: if keytab is lost, upload to
# https://codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com/credentials/store/system/domain/_/
# then set Use secret text above and set Bindings > Variable (path to the file) as ''' + CRW_KEYTAB + '''
chmod 700 ''' + CRW_KEYTAB + ''' && chown ''' + USER + ''' ''' + CRW_KEYTAB + '''
# create .k5login file
echo "crw-build/codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com@REDHAT.COM" > ~/.k5login
chmod 644 ~/.k5login && chown ''' + USER + ''' ~/.k5login
 echo "pkgs.devel.redhat.com,10.19.208.80 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAplqWKs26qsoaTxvWn3DFcdbiBxqRLhFngGiMYhbudnAj4li9/VwAJqLm1M6YfjOoJrj9dlmuXhNzkSzvyoQODaRgsjCG5FaRjuN8CSM/y+glgCYsWX1HFZSnAasLDuW0ifNLPR2RBkmWx61QKq+TxFDjASBbBywtupJcCsA5ktkjLILS+1eWndPJeSUJiOtzhoN8KIigkYveHSetnxauxv1abqwQTk5PmxRgRt20kZEFSRqZOJUlcl85sZYzNC/G7mneptJtHlcNrPgImuOdus5CW+7W49Z/1xqqWI/iRjwipgEMGusPMlSzdxDX4JzIx6R53pDpAwSAQVGDz4F9eQ==
" >> ~/.ssh/known_hosts

ssh-keyscan -t rsa github.com >> ~/.ssh/known_hosts

# see https://mojo.redhat.com/docs/DOC-1071739
if [[ -f ~/.ssh/config ]]; then mv -f ~/.ssh/config{,.BAK}; fi
echo "
GSSAPIAuthentication yes
GSSAPIDelegateCredentials yes

Host pkgs.devel.redhat.com
User crw-build/codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com@REDHAT.COM
" > ~/.ssh/config
chmod 600 ~/.ssh/config

# initialize kerberos
export KRB5CCNAME=/var/tmp/crw-build_ccache
kinit "crw-build/codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com@REDHAT.COM" -kt ''' + CRW_KEYTAB + '''
klist # verify working

hasChanged=0

SOURCEDOCKERFILE=${WORKSPACE}/sources/Dockerfile

# REQUIRE: skopeo
curl -L -s -S https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/''' + MIDSTM_BRANCH + '''/product/updateBaseImages.sh -o /tmp/updateBaseImages.sh
chmod +x /tmp/updateBaseImages.sh
cd ${WORKSPACE}/sources
  git checkout --track origin/''' + SOURCE_BRANCH + ''' || true
  export GITHUB_TOKEN=''' + GITHUB_TOKEN + ''' # echo "''' + GITHUB_TOKEN + '''"
  git config user.email "nickboldt+devstudio-release@gmail.com"
  git config user.name "Red Hat Devstudio Release Bot"
  git config --global push.default matching
  SOURCE_SHA=$(git rev-parse HEAD) # echo ${SOURCE_SHA:0:8}
cd ..

# get midstream repo sources
MIDSTM_REPO="''' + MIDSTM_REPO + '''"
if [[ ! -d ${WORKSPACE}/targetmid ]]; then git clone https://github.com/${MIDSTM_REPO} targetmid; fi
cd ${WORKSPACE}/targetmid
  git checkout --track origin/''' + MIDSTM_BRANCH + ''' || true
  git config user.email "nickboldt+devstudio-release@gmail.com"
  git config user.name "Red Hat Devstudio Release Bot"
  git config --global push.default matching
  MIDSTM_SHA=$(git rev-parse HEAD) # echo ${MIDSTM_SHA:0:8}

  # SOLVED :: Fatal: Could not read Username for "https://github.com", No such device or address :: https://github.com/github/hub/issues/1644
  git remote -v
  git config --global hub.protocol https
  git remote set-url origin https://\$GITHUB_TOKEN:x-oauth-basic@github.com/''' + MIDSTM_REPO + '''.git
  git remote -v
cd ..

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
          def SYNC_FILES_UP2DWN = ".dockerignore .gitignore cmd deploy deploy.sh e2e go.mod go.sum Gopkg.lock Gopkg.toml LICENSE olm pkg README.md templates vendor version"
          def SYNC_FILES_MID2DWN = "build"
          def SYNC_FILES_DWN2MID = "deploy"

          sh BOOTSTRAP

          OLD_SHA_MID = sh(script: '''#!/bin/bash -xe
          cd ${WORKSPACE}/targetmid; git rev-parse HEAD
          ''', returnStdout: true)
          println "Got OLD_SHA_MID in targetmid folder: " + OLD_SHA_MID

          OLD_SHA_DWN = sh(script: '''#!/bin/bash -xe
          cd ${WORKSPACE}/targetdwn; git rev-parse HEAD
          ''', returnStdout: true)
          println "Got OLD_SHA_DWN in targetdwn folder: " + OLD_SHA_DWN

          sh BOOTSTRAP + '''

# rsync files in upstream github to dist-git
for d in ''' + SYNC_FILES_UP2DWN + '''; do
  if [[ -f ${WORKSPACE}/sources/${d} ]]; then
    rsync -zrlt ${WORKSPACE}/sources/${d} ${WORKSPACE}/targetdwn/${d}
  elif [[ -d ${WORKSPACE}/sources/${d} ]]; then
    # copy over the files
    rsync -zrlt ${WORKSPACE}/sources/${d}/* ${WORKSPACE}/targetdwn/${d}/
    # sync the directory and delete from targetdwn if deleted from source
    rsync -zrlt --delete ${WORKSPACE}/sources/${d}/ ${WORKSPACE}/targetdwn/${d}/
  fi
done

# rsync files in midstream github to dist-git
for d in ''' + SYNC_FILES_MID2DWN + '''; do
  if [[ -f ${WORKSPACE}/targetmid/${d} ]]; then
    rsync -zrlt ${WORKSPACE}/targetmid/${d} ${WORKSPACE}/targetdwn/${d}
  elif [[ -d ${WORKSPACE}/targetmid/${d} ]]; then
    # copy over the files
    rsync -zrlt ${WORKSPACE}/targetmid/${d}/* ${WORKSPACE}/targetdwn/${d}/
    # sync the directory and delete from targetdwn if deleted from source
    rsync -zrlt --delete ${WORKSPACE}/targetmid/${d}/ ${WORKSPACE}/targetdwn/${d}/
  fi
done

'''
          // NEW way - requires yq
          sh BOOTSTRAP + '''
          sudo /usr/bin/python3 -m pip install --upgrade pip; sudo /usr/bin/python3 -m pip install yq
          jq --version
          yq --version
          CSV_VERSION="$(curl -sSLo - https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/''' + MIDSTM_BRANCH + '''/pom.xml | grep "<version>" | head -2 | tail -1 | \
            sed -r -e "s#.*<version>(.+)</version>.*#\\1#" -e "s#\\.GA##")" # 2.y.0 but not 2.y.0.GA
          ${WORKSPACE}/targetdwn/build/scripts/sync-che-operator-to-crw-operator.sh -v ${CSV_VERSION} -s ${WORKSPACE}/sources/ -t ${WORKSPACE}/targetmid/
          ${WORKSPACE}/targetdwn/build/scripts/sync-che-operator-to-crw-operator.sh -v ${CSV_VERSION} -s ${WORKSPACE}/sources/ -t ${WORKSPACE}/targetdwn/
          '''

          // get latest tags for the operator deployed images
          def opyaml = "${WORKSPACE}/targetdwn/deploy/operator.yaml"
          def images = [
            "registry.redhat.io/codeready-workspaces/server-rhel8",
            "registry.redhat.io/codeready-workspaces/pluginregistry-rhel8",
            "registry.redhat.io/codeready-workspaces/devfileregistry-rhel8",
            "registry.redhat.io/ubi8/ubi-minimal",
            "registry.redhat.io/rhel8/postgresql-96",
            "registry.redhat.io/rh-sso-7/sso74-openshift-rhel8",
            "registry.redhat.io/codeready-workspaces/pluginbroker-metadata-rhel8",
            "registry.redhat.io/codeready-workspaces/pluginbroker-artifacts-rhel8",
            "registry.redhat.io/codeready-workspaces/jwtproxy-rhel8"]
          result = readFile(opyaml)
          images.each() {
            latestTag = sh(returnStdout:true,script:"skopeo inspect docker://$it | jq -r .RepoTags[] | sort -V | egrep -v 'source|latest' | tail -1").trim()
            echo "[INFO] Got image+tag: $it : $latestTag"
            result.replaceAll("$it:.+", "$it:" + latestTag)
          }
          writeFile file: opyaml, text: result
          
          sh BOOTSTRAP + '''

# remove unneeded olm files
rm -fr ${WORKSPACE}/targetdwn/olm/eclipse-che-preview-openshift ${WORKSPACE}/targetdwn/olm/eclipse-che-preview-kubernetes

cp -f ${SOURCEDOCKERFILE} ${WORKSPACE}/targetdwn/Dockerfile

CRW_VERSION="''' + CRW_VERSION_F + '''"
#apply patches
sed -i ${WORKSPACE}/targetdwn/Dockerfile \
  -e "s#FROM registry.redhat.io/#FROM #g" \
  -e "s#FROM registry.access.redhat.com/#FROM #g" \
  -e "s/# *RUN yum /RUN yum /g" \

METADATA='ENV SUMMARY="Red Hat CodeReady Workspaces ''' + QUAY_PROJECT + ''' container" \\\r
    DESCRIPTION="Red Hat CodeReady Workspaces ''' + QUAY_PROJECT + ''' container" \\\r
    PRODNAME="codeready-workspaces" \\\r
    COMPNAME="''' + QUAY_PROJECT + '''" \r
LABEL summary="$SUMMARY" \\\r
      description="$DESCRIPTION" \\\r
      io.k8s.description="$DESCRIPTION" \\\r
      io.k8s.display-name=\"$DESCRIPTION" \\\r
      io.openshift.tags="$PRODNAME,$COMPNAME" \\\r
      com.redhat.component="$PRODNAME-rhel8-$COMPNAME-container" \\\r
      name="$PRODNAME/$COMPNAME" \\\r
      version="'$CRW_VERSION'" \\\r
      license="EPLv2" \\\r
      maintainer="Nick Boldt <nboldt@redhat.com>" \\\r
      io.openshift.expose-services="" \\\r
      com.redhat.delivery.appregistry="false" \\\r
      usage="" \r'

echo -e "$METADATA" >> ${WORKSPACE}/targetdwn/Dockerfile

# push changes in github to dist-git
cd ${WORKSPACE}/targetdwn
if [[ \$(git diff --name-only) ]]; then # file changed
	OLD_SHA_DWN=\$(git rev-parse HEAD) # echo ${OLD_SHA_DWN:0:8}
	git add Dockerfile ''' + SYNC_FILES_MID2DWN + ''' ''' + SYNC_FILES_UP2DWN + ''' . -A -f
  /tmp/updateBaseImages.sh -b ''' + DWNSTM_BRANCH + ''' --nocommit || true
  # note this might fail if we sync from a tag vs. a branch
  git commit -s -m "[sync] Update from ''' + SOURCE_REPO + ''' @ ${SOURCE_SHA:0:8} + ''' + MIDSTM_REPO + ''' @ ${MIDSTM_SHA:0:8}" \
    Dockerfile ''' + SYNC_FILES_MID2DWN + ''' ''' + SYNC_FILES_UP2DWN + ''' . || true
  git push origin ''' + DWNSTM_BRANCH + ''' || true
  NEW_SHA_DWN=\$(git rev-parse HEAD) # echo ${NEW_SHA_DWN:0:8}
  if [[ "${OLD_SHA_DWN}" != "${NEW_SHA_DWN}" ]]; then hasChanged=1; fi
  echo "[sync] Updated pkgs.devel @ ${NEW_SHA_DWN:0:8} from ''' + SOURCE_REPO + ''' @ ${SOURCE_SHA:0:8} + ''' + MIDSTM_REPO + ''' @ ${MIDSTM_SHA:0:8}"
else
    # file not changed, but check if base image needs an update
    # (this avoids having 2 commits for every change)
    cd ${WORKSPACE}/targetdwn
    OLD_SHA_DWN=\$(git rev-parse HEAD) # echo ${OLD_SHA_DWN:0:8}
    /tmp/updateBaseImages.sh -b ''' + DWNSTM_BRANCH + ''' || true
    NEW_SHA_DWN=\$(git rev-parse HEAD) # echo ${NEW_SHA_DWN:0:8}
    if [[ "${OLD_SHA_DWN}" != "${NEW_SHA_DWN}" ]]; then hasChanged=1; fi
    cd ..
fi
cd ..

# now rsync files to MIDSTM GH repo from changes in dist-git
for d in ''' + SYNC_FILES_DWN2MID + '''; do
  if [[ -f ${WORKSPACE}/targetdwn/${d} ]]; then
    rsync -zrlt ${WORKSPACE}/targetdwn/${d} ${WORKSPACE}/targetmid/${d}
  elif [[ -d ${WORKSPACE}/targetdwn/${d} ]]; then
    # copy over the files
    rsync -zrlt ${WORKSPACE}/targetdwn/${d}/* ${WORKSPACE}/targetmid/${d}/
    # sync the directory and delete from targetmid if deleted from source
    rsync -zrlt --delete ${WORKSPACE}/targetdwn/${d}/ ${WORKSPACE}/targetmid/${d}/
  fi
done

# push changes to github from dist-git
cd ${WORKSPACE}/targetmid
if [[ \$(git diff --name-only) ]]; then # file changed
	OLD_SHA_MID=\$(git rev-parse HEAD) # echo ${OLD_SHA_MID:0:8}
	git add ''' + SYNC_FILES_DWN2MID + '''
  /tmp/updateBaseImages.sh -b ''' + MIDSTM_BRANCH + ''' --nocommit
  # note this might fail if we sync from a tag vs. a branch
  git commit -s -m "[sync] Update from ''' + SOURCE_REPO + ''' @ ${SOURCE_SHA:0:8}" ''' + SYNC_FILES_DWN2MID + ''' || true
  git push origin ''' + MIDSTM_BRANCH + ''' || true
  NEW_SHA_MID=\$(git rev-parse HEAD) # echo ${NEW_SHA_MID:0:8}
  if [[ "${OLD_SHA_MID}" != "${NEW_SHA_MID}" ]]; then hasChanged=1; fi
  echo "[sync] Updated GH @ ${NEW_SHA_MID:0:8} from ''' + SOURCE_REPO + ''' @ ${SOURCE_SHA:0:8}"
else
    # file not changed, but check if base image needs an update
    # (this avoids having 2 commits for every change)
    cd ${WORKSPACE}/targetmid
    OLD_SHA_MID=\$(git rev-parse HEAD) # echo ${OLD_SHA_MID:0:8}
    /tmp/updateBaseImages.sh -b ''' + MIDSTM_BRANCH + '''
    NEW_SHA_MID=\$(git rev-parse HEAD) # echo ${NEW_SHA_MID:0:8}
    if [[ "${OLD_SHA_MID}" != "${NEW_SHA_MID}" ]]; then hasChanged=1; fi
    cd ..
fi
cd ..

if [[ ''' + FORCE_BUILD + ''' == "true" ]]; then hasChanged=1; fi
if [[ ${hasChanged} -eq 1 ]]; then
  for QRP in ''' + QUAY_PROJECT + '''; do
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

    curl \
"https://codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com/job/crwctl_''' + CRW_VERSION_F + '''/buildWithParameters?\
token=CI_BUILD&cause=build+crwctl+for+operator+sync+from+${BUILD_TAG}&versionSuffix=CI"
  done
fi

if [[ ${hasChanged} -eq 0 ]]; then
  echo "No changes upstream, nothing to commit"
fi
'''
        }
	        def NEW_SHA_MID = sh(script: '''#!/bin/bash -xe
	        cd ${WORKSPACE}/targetmid; git rev-parse HEAD
	        ''', returnStdout: true)
	        println "Got NEW_SHA_MID in targetmid folder: " + NEW_SHA_MID

	        def NEW_SHA_DWN = sh(script: '''#!/bin/bash -xe
	        cd ${WORKSPACE}/targetdwn; git rev-parse HEAD
	        ''', returnStdout: true)
	        println "Got NEW_SHA_DWN in targetdwn folder: " + NEW_SHA_DWN

	        if (NEW_SHA_MID.equals(OLD_SHA_MID) && NEW_SHA_DWN.equals(OLD_SHA_DWN) && !FORCE_BUILD.equals("true")) {
	          currentBuild.result='UNSTABLE'
	        }
    }
	}
}
