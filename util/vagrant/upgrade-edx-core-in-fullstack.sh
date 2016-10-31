#!/usr/bin/env bash

# Makes this more verbose.
set -x

# Stop if any command fails.
set -e

# Logging: write all the output to a timestamped log file.
sudo mkdir -p /var/log/edx
exec > >(sudo tee /var/log/edx/upgrade-$(date +%Y%m%d-%H%M%S).log) 2>&1

# defaults
CONFIGURATION="fullstack"
TARGET="open-release/eucalyptus.master"
OPENEDX_ROOT="/edx"

# Use this function to exit the script: it helps keep the output right with the
# exec-logging we started above.
exit_cleanly () {
  sleep .25
  echo
  exit $@
}

# Check we are in the right place, and have the info we need.
if [[ ! -d ${OPENEDX_ROOT}/app/edxapp ]]; then
  echo "Run this on your Open edX machine."
  exit_cleanly 1
fi

# check_pip succeeds if its first argument is found in the output of pip freeze.
PIP_EDXAPP="sudo -u edxapp -H $OPENEDX_ROOT/bin/pip.edxapp --disable-pip-version-check"
check_pip () {
  how_many=$($PIP_EDXAPP list 2>&- | grep -c "^$1 ")
  if (( $how_many > 0 )); then
    return 0
  else
    return 1
  fi
}

APPUSER=edxapp
if [[ $CONFIGURATION == fullstack ]] ; then
  APPUSER=www-data
fi

if [[ -f ${OPENEDX_ROOT}/app/edx_ansible/server-vars.yml ]]; then
  SERVER_VARS="--extra-vars=\"@${OPENEDX_ROOT}/app/edx_ansible/server-vars.yml\""
fi

# When tee'ing to a log, ansible (like many programs) buffers its output. This
# makes it hard to tell what is actually happening during the upgrade.
# "stdbuf -oL" will run ansible with line-buffered stdout, which makes the
# messages scroll in the way people expect.
ANSIBLE_PLAYBOOK="sudo stdbuf -oL ansible-playbook --inventory-file=localhost, --connection=local "

make_config_venv () {
  virtualenv venv
  source venv/bin/activate
  pip install -r configuration/pre-requirements.txt
  pip install -r configuration/requirements.txt
}

TEMPDIR=`mktemp -d`
echo "Working in $TEMPDIR"
chmod 777 $TEMPDIR
cd $TEMPDIR
# Set the CONFIGURATION_TARGET environment variable to use a different branch
# in the configuration repo, defaults to $TARGET.
git clone https://github.com/danilkuznetsov/configuration.git \
  --depth=1 --single-branch --branch="open-release/eucalyptus.juja"
make_config_venv

# Eucalyptus details

  if check_pip edx-oauth2-provider ; then
    echo "Uninstall edx-oauth2-provider"
    $PIP_EDXAPP uninstall -y edx-oauth2-provider
  fi
  if check_pip django-oauth2-provider ; then
    echo "Uninstall django-oauth2-provider"
    $PIP_EDXAPP uninstall -y django-oauth2-provider
  fi

  # edx-milestones changed how it was installed, so it is possible to have it
  # installed twice.  Try to uninstall it twice.
  if check_pip edx-milestones ; then
    echo "Uninstall edx-milestones"
    $PIP_EDXAPP uninstall -y edx-milestones
  fi
  if check_pip edx-milestones ; then
    echo "Uninstall edx-milestones again"
    $PIP_EDXAPP uninstall -y edx-milestones
  fi

  echo "Upgrade the code"
  cd configuration/playbooks/vagrant
  $ANSIBLE_PLAYBOOK \
    $SERVER_VARS \
    --extra-vars="edx_platform_version=$TARGET" \
    --extra-vars="xqueue_version=$TARGET" \
    --extra-vars="migrate_db=no" \
    --skip-tags="edxapp-sandbox,gather_static_assets" \
    vagrant-$CONFIGURATION-delta.yml
  cd ../../..

  echo "Migrate to fix oauth2_provider"
  ${OPENEDX_ROOT}/bin/edxapp-migrate-lms --fake oauth2_provider zero
  ${OPENEDX_ROOT}/bin/edxapp-migrate-lms --fake-initial

# Update to target.
echo "Updating to final version of code"
cd configuration/playbooks
echo "edx_platform_version: $TARGET" > vars.yml
echo "xqueue_version: $TARGET" >> vars.yml
$ANSIBLE_PLAYBOOK \
    --extra-vars="@vars.yml" \
    $SERVER_VARS \
    --skip-tags="edxapp-sandbox" \
    vagrant-update-core-$CONFIGURATION.yml
cd ../..

# Post-upgrade work.
cd /
sudo rm -rf $TEMPDIR
echo "Upgrade complete. Please reboot your machine."