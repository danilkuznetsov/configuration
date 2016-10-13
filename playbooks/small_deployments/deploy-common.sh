#!/bin/sh

##
## Run the deploy-common.yml playbook in the configuration/playbooks directory
##
cd /var/tmp/configuration/playbooks/small_deployments/  && sudo ansible-playbook -c local ./deploy-common.yml -i "localhost," -e@ansible_overrides.yml