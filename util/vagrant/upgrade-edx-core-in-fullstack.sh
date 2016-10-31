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
TARGET="named-release/cypress"
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

  # Needed if transitioning to Cypress.
  echo "Killing all celery worker processes."
  sudo ${OPENEDX_ROOT}/bin/supervisorctl stop edxapp_worker:* &
  sleep 3
  # Supervisor restarts the process a couple of times so we have to kill it multiple times.
  sudo pgrep -lf celery | grep worker | awk '{ print $1}' | sudo xargs -I {} kill -9 {}
  sleep 3
  sudo pgrep -lf celery | grep worker | awk '{ print $1}' | sudo xargs -I {} kill -9 {}
  sleep 3
  sudo pgrep -lf celery | grep worker | awk '{ print $1}' | sudo xargs -I {} kill -9 {}
  sleep 3
  sudo pgrep -lf celery | grep worker | awk '{ print $1}' | sudo xargs -I {} kill -9 {}

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

# Clone our configuration repository
git clone https://github.com/danilkuznetsov/configuration.git \
  --depth=1 --single-branch --branch="named-release/cypress.juja"
make_config_venv

# Remove old venvs
sudo -u edxapp rm -rf /edx/app/edxapp/venvs/edxapp
sudo -u xqueue rm -rf /edx/app/xqueue/venvs/xqueue

# Update to target.

echo "Updating to final version of code"
cd configuration/playbooks
echo "edx_platform_version: $TARGET" > vars.yml
echo "certs_version: $TARGET" >> vars.yml
echo "forum_version: $TARGET" >> vars.yml
echo "xqueue_version: $TARGET" >> vars.yml
echo "demo_version: $TARGET" >> vars.yml
echo "NOTIFIER_VERSION: $TARGET" >> vars.yml
echo "ECOMMERCE_VERSION: $TARGET" >> vars.yml
echo "ECOMMERCE_WORKER_VERSION: $TARGET" >> vars.yml
echo "PROGRAMS_VERSION: $TARGET" >> vars.yml
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