#!/usr/bin/env bash

# WARNING: DO NOT EDIT!
#
# This file was generated by plugin_template, and is managed by bootstrap.py. Please use
# bootstrap.py to update this file.
#
# For more info visit https://github.com/pulp/plugin_template

set -v

if [ "$TEST" = 'docs' ]; then

  pip3 install -r pulp_rpm.egg-info/requires.txt
  pip3 install -r ../pulpcore/doc_requirements.txt

  pip3 install -r doc_requirements.txt
  pip3 install -r ../pulpcore/pulpcore.egg-info/requires.txt
  pip3 install -r ../pulpcore/pulpcore.egg-info/requires.txt[postgres]
fi

pip install -r test_requirements.txt

cd $TRAVIS_BUILD_DIR/../pulpcore/containers/

# If we are on a PR
if [ -n "$TRAVIS_PULL_REQUEST_BRANCH" ]; then
  TAG=$TRAVIS_PULL_REQUEST_BRANCH
# For push builds, tag builds, and hopefully cron builds
elif [ -n "$TRAVIS_BRANCH" ]; then
  TAG=$TRAVIS_BRANCH
  if [ "$TAG" = "master" ]; then
    TAG=latest
  fi
else
  # Fallback
  TAG=$(git rev-parse --abbrev-ref HEAD)
fi


PLUGIN=pulp_rpm


# For pulpcore, and any other repo that might check out a pulp-certguard PR
if [ -e $TRAVIS_BUILD_DIR/../pulp-certguard ]; then
  PULP_CERTGUARD=./pulp-certguard
else
  # Otherwise, stable release
  PULP_CERTGUARD=pulp-certguard
fi

cat > vars/vars.yaml << VARSYAML
---
images:
  - ${PLUGIN}-${TAG}:
      image_name: $PLUGIN
      tag: $TAG
      pulpcore: ./pulpcore
      pulpcore_plugin: ./pulpcore-plugin
      plugins:
        - $PULP_CERTGUARD
        - ./$PLUGIN
VARSYAML

ansible-playbook build.yaml

cd $TRAVIS_BUILD_DIR/../pulp-operator
# Tell pulp-perator to deploy our image
cat > deploy/crds/pulpproject_v1alpha1_pulp_cr.yaml << CRYAML
apiVersion: pulpproject.org/v1alpha1
kind: Pulp
metadata:
  name: example-pulp
spec:
  pulp_file_storage:
    # k3s local-path requires this
    access_mode: "ReadWriteOnce"
    # We have a little over 40GB free on Travis VMs/instances
    size: "40Gi"
  image: $PLUGIN
  tag: $TAG
CRYAML

# Install k3s, lightweight Kubernetes
.travis/k3s-install.sh
# Deploy pulp-operator, with the pulp containers, according to CRYAML
sudo ./up.sh

# Needed for the script below
# Since it is being run during install rather than actual tests (unlike in 
# pulp-operator), and therefore does not trigger the equivalent after_failure
# travis commands.
show_logs_and_return_non_zero() {
    readonly local rc="$?"

    for containerlog in "pulp-api" "pulp-content" "pulp-resource-manager" "pulp-worker"
    do
      echo -en "travis_fold:start:$containerlog"'\\r'
      sudo kubectl logs -l app=$containerlog --tail=10000
      echo -en "travis_fold:end:$containerlog"'\\r'
    done

    return "${rc}"
}
.travis/pulp-operator-check-and-wait.sh
