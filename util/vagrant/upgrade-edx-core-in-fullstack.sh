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
TARGET="named-release/dogwood.rc"
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

# Clone our configuration repositoryT.
git clone https://github.com/danilkuznetsov/configuration.git \
  --depth=1 --single-branch --branch="named-release/dogwood.juja"
make_config_venv

# Dogwood details

cat > migrate-008-context.js <<"EOF"
    // from: https://github.com/edx/cs_comments_service/blob/master/scripts/db/migrate-008-context.js
    print ("Add the new indexes for the context field");
    db.contents.ensureIndex({ _type: 1, course_id: 1, context: 1, pinned: -1, created_at: -1 }, {background: true})
    db.contents.ensureIndex({ _type: 1, commentable_id: 1, context: 1, pinned: -1, created_at: -1 }, {background: true})

    print ("Adding context to all comment threads where it does not yet exist\n");
    var bulk = db.contents.initializeUnorderedBulkOp();
    bulk.find( {_type: "CommentThread", context: {$exists: false}} ).update(  {$set: {context: "course"}} );
    bulk.execute();
    printjson (db.runCommand({ getLastError: 1, w: "majority", wtimeout: 5000 } ));
EOF

  mongo cs_comments_service migrate-008-context.js

  # We are upgrading Python from 2.7.3 to 2.7.10, so remake the venvs.
  sudo rm -rf ${OPENEDX_ROOT}/app/*/v*envs/*

  echo "Upgrading to the end of Django 1.4"
  cd configuration/playbooks/vagrant
  $ANSIBLE_PLAYBOOK \
    $SERVER_VARS \
    --extra-vars="edx_platform_version=release-2015-11-09" \
    --extra-vars="xqueue_version=named-release/cypress" \
    --extra-vars="migrate_db=yes" \
    --skip-tags="edxapp-sandbox,gather_static_assets" \
    vagrant-$CONFIGURATION-delta.yml
  cd ../../..

  # Remake our own venv because of the Python 2.7.10 upgrade.
  rm -rf venv
  make_config_venv

  # Need to get rid of South from edx-platform, or things won't work.
  $PIP_EDXAPP uninstall -y South

  $PIP_EDXAPP uninstall -y numpy
  $PIP_EDXAPP install "numpy==1.6.2"
  $PIP_EDXAPP uninstall -y scipy
  $PIP_EDXAPP install  "scipy==0.14.0"
  $PIP_EDXAPP uninstall -y sympy
  $PIP_EDXAPP install  "sympy==0.7.1"

  echo "Upgrading to the beginning of Django 1.8"
  cd configuration/playbooks/vagrant
  $ANSIBLE_PLAYBOOK \
    $SERVER_VARS \
    --extra-vars="edx_platform_version=dogwood-first-18" \
    --extra-vars="xqueue_version=dogwood-first-18" \
    --extra-vars="migrate_db=no" \
    --skip-tags="edxapp-sandbox,gather_static_assets" \
    vagrant-$CONFIGURATION-delta.yml
  cd ../../..

  echo "Running the Django 1.8 faked migrations"
  for item in lms cms; do
    sudo -u $APPUSER -E ${OPENEDX_ROOT}/bin/python.edxapp \
      ${OPENEDX_ROOT}/bin/manage.edxapp $item migrate --settings=aws --noinput --fake-initial
  done


 sudo -u xqueue \
    SERVICE_VARIANT=xqueue \
    ${OPENEDX_ROOT}/app/xqueue/venvs/xqueue/bin/python \
    ${OPENEDX_ROOT}/app/xqueue/xqueue/manage.py migrate \
    --settings=xqueue.aws_settings --noinput --fake-initial


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

echo "Running data fixup management commands"
sudo -u $APPUSER -E ${OPENEDX_ROOT}/bin/python.edxapp \
  ${OPENEDX_ROOT}/bin/manage.edxapp lms --settings=aws generate_course_overview --all

sudo -u $APPUSER -E ${OPENEDX_ROOT}/bin/python.edxapp \
  ${OPENEDX_ROOT}/bin/manage.edxapp lms --settings=aws post_cohort_membership_fix --commit

# Run the forums migrations again to catch things made while this script
# was running.
mongo cs_comments_service migrate-008-context.js

cd /
sudo rm -rf $TEMPDIR
echo "Upgrade complete. Please reboot your machine."