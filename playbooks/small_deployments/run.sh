#!/usr/bin/env bash

# Makes this more verbose.
set -x

# Stop if any command fails.
set -eset -x

BASE_DIR = "/var/tmp/edx-install"
TYPE = "application"

show_help () {
  cat << EOM

Install or Upgrades open edx node.

-t TYPE
    Type node: application, common, datasource
-h
    Show this help and exit.

EOM
}

# override defaults with options
while getopts "h:t" opt; do
  case "$opt" in
    h)
      show_help
      exit 0
      ;;
    t)
      TYPE=$OPTARG
      ;;
  esac
done

if [[ -d ${BASE_DIR} ]]; then
      ##
      ## Update configuration  repository
      ##
      cd $BASE_DIR/configuration
      git pull origin open-release/eucalyptus.juja

      ##
      ## Update private settings repository
      ##
      cd $BASE_DIR/secure
      git pull origin master
else
      echo "Create base directory and install configuration"
      mkdir -p $BASE_DIR
      cd $BASE_DIR

      ##
      ## Set ppa repository source for gcc/g++ 4.8 in order to install insights properly
      ##
      sudo apt-get install -y python-software-properties
      sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test

      ##
      ## Update and Upgrade apt packages
      ##
      sudo apt-get update -y
      sudo apt-get upgrade -y

      ##
      ## Install system pre-requisites
      ##
      sudo apt-get install -y build-essential software-properties-common curl git-core libxml2-dev libxslt1-dev python-pip libmysqlclient-dev python-apt python-dev libxmlsec1-dev libfreetype6-dev swig gcc-4.8 g++-4.8
      sudo pip install --upgrade pip==8.1.2
      sudo pip install --upgrade setuptools==24.0.3
      sudo -H pip install --upgrade virtualenv==15.0.2

      ##
      ## Update alternatives so that gcc/g++ 4.8 is the default compiler
      ##
      sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-4.8 50
      sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-4.8 50

      ##
      ## Clone the configuration repository
      ##
      git clone https://github.com/danilkuznetsov/configuration

      ##
      ## Clone the private settings repository
      ##
      git clone https://bitbucket.org/dkuznetcov/juja-private-settings secure

      ##
      ## Install the ansible requirements
      ##
      cd $BASE_DIR/configuration
      git checkout open-release/eucalyptus.juja
      sudo -H pip install -r requirements.txt

fi

##
## Install the ansible requirements
##

cd $BASE_DIR/configuration/playbooks/small_deployments/  && sudo ansible-playbook -c local ./deploy-${TYPE}.yml -i "localhost," -e@$BASE_DIR/secure/edx_overrides/ansible_overrides.yml