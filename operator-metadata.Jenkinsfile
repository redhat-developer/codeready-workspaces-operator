#!/usr/bin/env groovy

// PARAMETERS for this pipeline:
// CSV_VERSION_CHE = latest Che CSV to use to generate CRW CSV, eg., a nightly like 9.9.9-nightly.1594657566 or an actual release like 7.15.2
// CSV_VERSION_PREV = "2.2.0"
// SOURCE_BRANCH = "7.16.x" or "master" // branch of source repo from which to find and sync commits to pkgs.devel repo
// FORCE_BUILD = "false"

def SOURCE_REPO = "eclipse/che-operator" //source repo from which to find and sync commits to pkgs.devel repo

def MIDSTM_REPO = "redhat-developer/codeready-workspaces-operator" //source repo from which to find and sync commits to pkgs.devel repo
def DWNSTM_REPO = "containers/codeready-workspaces-operator-metadata" // dist-git repo to use as target

def MIDSTM_BRANCH = "master"         // target branch in GH repo, eg., master or 2.2.x
def DWNSTM_BRANCH = "crw-2.2-rhel-8" // target branch in dist-git repo, eg., crw-2.2-rhel-8
def SCRATCH = "false"
def PUSH_TO_QUAY = "true"
def QUAY_PROJECT = "operator-metadata" // also used for the Brew dockerfile params

def OLD_SHA_DWN=""

def buildNode = "rhel7-releng" // slave label
timeout(120) {
	node("${buildNode}"){ stage "Sync repos"
    cleanWs()
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
          checkout([$class: 'GitSCM',
            branches: [[name: "${MIDSTM_BRANCH}"]],
            doGenerateSubmoduleConfigurations: false,
            credentialsId: 'devstudio-release',
            poll: true,
            extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: "targetmid"]],
            submoduleCfg: [],
            userRemoteConfigs: [[url: "https://github.com/${MIDSTM_REPO}.git"],
                [credentialsId:'devstudio-release']
                ]])



            sh "sudo /usr/bin/python3 -m pip install --upgrade pip; sudo /usr/bin/python3 -m pip install yq jsonschema"
            def BOOTSTRAP = '''#!/bin/bash -xe

# bootstrapping: if keytab is lost, upload to
# https://codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com/credentials/store/system/domain/_/
# then set Use secret text above and set Bindings > Variable (path to the file) as ''' + CRW_KEYTAB + '''
chmod 700 ''' + CRW_KEYTAB + ''' && chown ''' + USER + ''' ''' + CRW_KEYTAB + '''
# create .k5login file
echo "crw-build/codeready-workspaces-jenkins.rhev-ci-vms.eng.rdu2.redhat.com@REDHAT.COM" > ~/.k5login
chmod 644 ~/.k5login && chown ''' + USER + ''' ~/.k5login
 echo "pkgs.devel.redhat.com,10.16.101.66 ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAplqWKs26qsoaTxvWn3DFcdbiBxqRLhFngGiMYhbudnAj4li9/VwAJqLm1M6YfjOoJrj9dlmuXhNzkSzvyoQODaRgsjCG5FaRjuN8CSM/y+glgCYsWX1HFZSnAasLDuW0ifNLPR2RBkmWx61QKq+TxFDjASBbBywtupJcCsA5ktkjLILS+1eWndPJeSUJiOtzhoN8KIigkYveHSetnxauxv1abqwQTk5PmxRgRt20kZEFSRqZOJUlcl85sZYzNC/G7mneptJtHlcNrPgImuOdus5CW+7W49Z/1xqqWI/iRjwipgEMGusPMlSzdxDX4JzIx6R53pDpAwSAQVGDz4F9eQ==
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

SOURCEDOCKERFILE=${WORKSPACE}/targetmid/operator-metadata.Dockerfile

# REQUIRE: skopeo
curl -L -s -S https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/master/product/updateBaseImages.sh -o /tmp/updateBaseImages.sh
chmod +x /tmp/updateBaseImages.sh

cd ${WORKSPACE}/sources
  git checkout --track origin/''' + SOURCE_BRANCH + ''' || true
  git config user.email "nickboldt+devstudio-release@gmail.com"
  git config user.name "Red Hat Devstudio Release Bot"
  git config --global push.default matching
  SOURCE_SHA=$(git rev-parse HEAD) # echo ${SOURCE_SHA:0:8}
cd ..

cd ${WORKSPACE}/targetmid
  git checkout --track origin/''' + MIDSTM_BRANCH + ''' || true
  export GITHUB_TOKEN=''' + GITHUB_TOKEN + ''' # echo "''' + GITHUB_TOKEN + '''"
  git config user.email nickboldt+devstudio-release@gmail.com
  git config user.name "devstudio-release"
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
CSV_VERSION="$(curl -sSLo - https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/master/pom.xml | grep "<version>" | head -2 | tail -1 | \
  sed -r -e "s#.*<version>(.+)</version>.*#\\1#" -e "s#\\.GA##")" # 2.3.0 but not 2.3.0.GA
CSV_FILE="\$( { find ${WORKSPACE}/targetdwn/manifests/ -name "${CSV_NAME}.csv.yaml" | tail -1; } || true)"; # echo "[INFO] CSV = ${CSV_FILE}"
if [[ ! ${CSV_FILE} ]]; then 
  # CRW-878 generate CSV and update CRD from upstream
  cd ${WORKSPACE}/targetmid/build/scripts
  ./sync-che-olm-to-crw-olm.sh -v ${CSV_VERSION} -p ''' + CSV_VERSION_PREV + ''' -s ${WORKSPACE}/sources -t ${WORKSPACE}/targetmid --che ''' + CSV_VERSION_CHE + '''
  cd ${WORKSPACE}/targetmid/
  # if anything has changed other than the createdAt date, then we commit this
  if [[ $(git diff | grep -v createdAt | egrep "^(-|\\+) ") ]]; then
    git add manifests/ build/scripts/
    git commit -s -m "[csv] Add CSV ${CSV_VERSION}" manifests/ build/scripts/
    git push origin ''' + MIDSTM_BRANCH + '''
  else # no need to push this so revert
    git checkout manifests/ build/scripts/
  fi
fi

cd ${WORKSPACE}/targetmid
/tmp/updateBaseImages.sh -b ''' + MIDSTM_BRANCH + ''' -f ${SOURCEDOCKERFILE##*/} -maxdepth 1 || true
cd ..
'''
              }

          def SYNC_FILES_MID2DWN = "controller-manifests manifests metadata build" // folders in mid/dwn

          OLD_SHA_DWN = sh(script: BOOTSTRAP + '''
          cd ${WORKSPACE}/targetdwn; git rev-parse HEAD
          ''', returnStdout: true)
          println "Got OLD_SHA_DWN in targetdwn folder: " + OLD_SHA_DWN

          sh BOOTSTRAP + '''
# rsync files in github midstream to dist-git downstream
# TODO CRW 2.3 / OCP 4.6 switch to use manifests metadata folders
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

cp -f ${SOURCEDOCKERFILE} ${WORKSPACE}/targetdwn/Dockerfile

# TODO should this be a branch instead of just master?
CRW_VERSION=`wget -qO- https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/master/dependencies/VERSION`
#apply patches
sed -i ${WORKSPACE}/targetdwn/Dockerfile \
  -e "s#FROM registry.redhat.io/#FROM #g" \
  -e "s#FROM registry.access.redhat.com/#FROM #g" \
  -e "s/# *RUN yum /RUN yum /g" \

# generate digests from tags
# 1. convert csv to use brew container refs so we can resolve stuff
CSV_NAME="codeready-workspaces"
CSV_VERSION="$(curl -sSLo - https://raw.githubusercontent.com/redhat-developer/codeready-workspaces/master/pom.xml | grep "<version>" | head -2 | tail -1 | \
  sed -r -e "s#.*<version>(.+)</version>.*#\\1#" -e "s#\\.GA##")" # 2.3.0 but not 2.3.0.GA
CSV_FILE="\$(find ${WORKSPACE}/targetdwn/manifests/ -name "${CSV_NAME}.csv.yaml" | tail -1)"; # echo "[INFO] CSV = ${CSV_FILE}"
sed -r \
    `# for plugin & devfile registries, use internal Brew versions` \
    -e "s|registry.redhat.io/codeready-workspaces/(pluginregistry-rhel8:.+)|registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-\\1|g" \
    -e "s|registry.redhat.io/codeready-workspaces/(devfileregistry-rhel8:.+)|registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-\\1|g" \
    `# in all other cases (including operator) use published quay images to compute digests` \
    -e "s|registry.redhat.io/codeready-workspaces/(.+)|quay.io/crw/\\1|g" \
    -i "${CSV_FILE}"

# 2. generate digests
pushd ${WORKSPACE}/targetdwn >/dev/null
# TODO digest scripts from upstream do not work - https://github.com/eclipse/che/issues/17432
# ./build/scripts/addDigests.sh -s manifests -r ".*.csv.yaml" -t ${CRW_VERSION}

# TODO make sure generated CSV is not mangled by yq

# TODO CRW-1044 merge in upstream disgest scripts here
./build/scripts/addDigests.sh -s controller-manifests -n codeready-workspaces -v ${CSV_VERSION} -t ${CRW_VERSION}
popd >/dev/null

# 3. revert to OSBS image refs, since digest pinning will automatically switch them to RHCC values
# TODO CRW-1162 re-enable when using OSBS digest pinning, not homegrown variant
#sed -r \
#    -e "s#(quay.io/crw/|registry.redhat.io/codeready-workspaces/)#registry-proxy.engineering.redhat.com/rh-osbs/codeready-workspaces-#g" \
#    -i "${CSV_FILE}"

# TODO CRW-1044 switch to operators.operatorframework.io.bundle LABELs
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
      com.redhat.delivery.appregistry="true" \\\r
      usage="" \r'

echo -e "$METADATA" >> ${WORKSPACE}/targetdwn/Dockerfile

# push changes in github to dist-git
cd ${WORKSPACE}/targetdwn
if [[ \$(git diff --name-only) ]]; then # file changed
	OLD_SHA_DWN=\$(git rev-parse HEAD) # echo ${OLD_SHA_DWN:0:8}
	git add Dockerfile ''' + SYNC_FILES_MID2DWN + '''
    /tmp/updateBaseImages.sh -b ''' + DWNSTM_BRANCH + ''' --nocommit
  git commit -s -m "[sync] Update from ''' + SOURCE_REPO + ''' @ ${SOURCE_SHA:0:8} + ''' + MIDSTM_REPO + ''' @ ${MIDSTM_SHA:0:8}" \
    Dockerfile ''' + SYNC_FILES_MID2DWN + ''' || true
	git push origin ''' + DWNSTM_BRANCH + '''
	NEW_SHA_DWN=\$(git rev-parse HEAD) # echo ${NEW_SHA_DWN:0:8}
	if [[ "${OLD_SHA_DWN}" != "${NEW_SHA_DWN}" ]]; then hasChanged=1; fi
  echo "[sync] Updated pkgs.devel @ ${NEW_SHA_DWN:0:8} from ''' + SOURCE_REPO + ''' @ ${SOURCE_SHA:0:8} + ''' + MIDSTM_REPO + ''' @ ${MIDSTM_SHA:0:8}"
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

# NOTE: this image needs to build in Brew, then rebuild for Quay, so use QUAY_REBUILD_PATH instead of QUAY_REPO_PATHs variable
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
QUAY_REBUILD_PATH=${QUAY_REPO_PATH}&\
JOB_BRANCH=master&\
FORCE_BUILD=true&\
SCRATCH=''' + SCRATCH + '''"
  done
fi

if [[ ${hasChanged} -eq 0 ]]; then
  echo "No changes upstream, nothing to commit"
fi
'''
        }
	        def NEW_SHA_DWN = sh(script: '''#!/bin/bash -xe
	        cd ${WORKSPACE}/targetdwn; git rev-parse HEAD
	        ''', returnStdout: true)
	        println "Got NEW_SHA_DWN in targetdwn folder: " + NEW_SHA_DWN

	        if (NEW_SHA_DWN.equals(OLD_SHA_DWN)) {
	          currentBuild.result='UNSTABLE'
	        }
	}
}
