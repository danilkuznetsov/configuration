#!/bin/sh

##
## Run the deploy-application.yml playbook in the configuration/playbooks directory
##
cd /var/tmp/configuration/playbooks && sudo ansible-playbook -c local ./deploy-application.yml -i "localhost," -e@/ansible_overrides.yml