#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")" && cd ..
# all paths relative to project root from here

lsblk
read -p "Enter the partition path to the public ca device (must be persistent and already formatted, e.g. a 2nd USB stick) [/dev/sdb1]: " PUBLIC_CA_PART
PUBLIC_CA_PART=${PUBLIC_CA_PART:-/dev/sdb1}

sudo mkdir -p /mnt/public_ca
sudo mount $PUBLIC_CA_PART /mnt/public_ca

export STEPPATH=/etc/step-ca
sudo --preserve-env step ca init --name="fca" \
    --dns="fca.home.arpa,192.168.2.9" --address=":443" \
    --provisioner="fca@fnas.home.arpa" \
    --deployment-type standalone \
    --remote-management

sudo chown -R step:step /etc/step-ca/

sudo -su step bash -c "STEPPATH=/etc/step-ca step-ca"

sudo cp /mnt/public_ca/tiny-ca_public_certs/intermediate_ca.crt /mnt/public_ca/tiny-ca_public_certs/root_ca.crt /etc/step-ca/certs
sudo umount /mnt/public_ca

sudo mv /etc/step-ca/config/ca.json /etc/step-ca/config/ca.json.bak

sudo bash -c "jq -s 'add' /etc/step-ca/config/ca.json.bak templates/ca.part.json > /etc/step-ca/config/ca.json"

sudo chown -R step:step /etc/step-ca/

sudo install templates/step-ca.service /etc/systemd/system/step-ca.service
sudo systemctl daemon-reload
sudo systemctl enable --now step-ca.service
