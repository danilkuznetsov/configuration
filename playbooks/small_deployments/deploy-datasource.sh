#!/bin/sh

##
## Run the deploy-datasource.yml playbook in the configuration/playbooks directory
##
cd /var/tmp/configuration/playbooks/small_deployments/  && sudo ansible-playbook -c local ./deploy-datasource.yml -i "localhost," -e@ansible_overrides.yml