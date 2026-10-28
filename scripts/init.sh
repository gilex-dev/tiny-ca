#!/bin/bash
cd "$(dirname "${BASH_SOURCE[0]}")" && cd ..
# all paths relative to project root from here

lsblk

read -p "Enter the device path to the offline ca device [/dev/sda]: " OFFLINE_CA_DEV
OFFLINE_CA_DEV=${OFFLINE_CA_DEV:-/dev/sda}

read -p "Enter the partition path to the public ca device (must be persistent and already formatted, e.g. a 2nd USB stick) [/dev/sdb1]: " PUBLIC_CA_PART
PUBLIC_CA_PART=${PUBLIC_CA_PART:-/dev/sdb1}

read -p "This will erase all data on $OFFLINE_CA_DEV. Type 'yes' in all-caps to proceed: " yn

case $yn in
YES) echo proceeding ;;
*)
    echo aborting
    exit
    ;;
esac

sudo mkdir -p /mnt/public_ca
sudo mount $PUBLIC_CA_PART /mnt/public_ca

IS_OVERLAY=$(raspi-config nonint get_overlay_now)
if [ $IS_OVERLAY -eq 1 ]; then
    echo "Error: fs not in read-only mode."
    exit 1
fi

echo "Loading pico-rng driver"
sudo insmod bin/pico_rng.ko debug=1 && sleep 5

echo "Formatting device"
sudo sfdisk --wipe always $OFFLINE_CA_DEV <<'EOF'
label: gpt
, , L
EOF

LUKS_PW=$(pwgen -s 32 1)
echo $LUKS_PW | sudo cryptsetup luksFormat --key-file - --type luks2 $OFFLINE_CA_DEV"1"
echo $LUKS_PW | sudo cryptsetup open --key-file - $OFFLINE_CA_DEV"1" offline_root_ca

OFFLINE_CA_MOUNT_PATH=/mnt/offline_root_ca
echo "Creating fs"
sudo mkfs.btrfs -L offline_root_ca /dev/mapper/offline_root_ca
sudo mkdir -p $OFFLINE_CA_MOUNT_PATH
sudo mount /dev/mapper/offline_root_ca $OFFLINE_CA_MOUNT_PATH
CA_USER=$(whoami)
export STEPPATH=$OFFLINE_CA_MOUNT_PATH/ca
sudo install -o $CA_USER -d $STEPPATH

STEP_CA_KEY_PW=$(pwgen -s 32 1)
echo $STEP_CA_KEY_PW >/tmp/STEP_CA_KEY_PW

echo "Creating new pki"
step ca init --pki --name="fca" --deployment-type standalone --password-file /tmp/STEP_CA_KEY_PW

sudo rmmod pico_rng

read -p "Put the pico into flash mode now (hold the BOOT button while pressing RESET). Then press enter"

sleep 4 && lsblk

read -p "Enter the path to the pico's partition [/dev/sdc1]: " PICO_PART_PATH
PICO_PART_PATH=${PICO_PART_PATH:-/dev/sdc1}

sudo mkdir -p /mnt/pico
sudo mount $PICO_PART_PATH /mnt/pico
sudo cp bin/pico_hsm_pico2.uf2 /mnt/pico
sudo umount /mnt/pico

read -p "Reset the pico (press the RESET button). Then press enter"

PICO_SO_PIN=$(echo -n $(pwgen -s 8 1) | od -A n -t x1 | sed 's/ *//g') # TODO: check so-pin requirements again
PICO_PIN=$(sudo cat /etc/step-ca/hsm-pin.txt)
sudo chown step:step /etc/step-ca/hsm-pin.txt
sudo chmod u=r,g=,o= /etc/step-ca/hsm-pin.txt

sudo sc-hsm-tool --initialize --so-pin $PICO_SO_PIN --pin $PICO_PIN

HSM_KEY_NUM=1
PKCS_MODUKE_PATH=/usr/lib/arm-linux-gnueabihf/pkcs11/opensc-pkcs11.so
sudo pkcs11-tool --module $PKCS_MODUKE_PATH \
    --keypairgen --key-type EC:prime256v1 \
    --login --pin $PICO_PIN \
    --id $HSM_KEY_NUM --label "Intermediate HSM Key"

sudo mv /mnt/offline_root_ca/ca/certs/intermediate_ca.crt /mnt/offline_root_ca/ca/certs/intermediate_ca.crt.pre_pico.bak

sudo step certificate create \
    --profile intermediate-ca \
    --kms "pkcs11:module-path=$PKCS_MODUKE_PATH;token=Pico-HSM;pin-value=$PICO_PIN" \
    --key "pkcs11:id=$HSM_KEY_NUM;type=private" \
    "Intermediate CA" \
    $OFFLINE_CA_MOUNT_PATH/ca/certs/intermediate_ca.crt \
    --ca $OFFLINE_CA_MOUNT_PATH/ca/certs/root_ca.crt \
    --ca-key $OFFLINE_CA_MOUNT_PATH/ca/secrets/root_ca_key \
    --ca-password-file /tmp/STEP_CA_KEY_PW

sudo shred /tmp/STEP_CA_KEY_PW

sudo mkdir -p /mnt/public_ca/tiny-ca_public_certs
sudo cp $OFFLINE_CA_MOUNT_PATH/ca/certs/root_ca.crt $OFFLINE_CA_MOUNT_PATH/ca/certs/intermediate_ca.crt /mnt/public_ca/tiny-ca_public_certs

sudo umount /mnt/public_ca
sudo umount $OFFLINE_CA_MOUNT_PATH
sudo cryptsetup close offline_root_ca

while [[ "$input" != "$LUKS_PW" ]]; do
    read -rp "Write down and enter the offline luks2 password again $LUKS_PW:" input
done

while [[ "$input" != "$STEP_CA_KEY_PW" ]]; do
    read -rp "Write down and enter the offline keyfile password again $STEP_CA_KEY_PW:" input
done

while [[ "$input" != "$PICO_PIN" ]]; do
    read -rp "Write down and enter the pico pin again $PICO_PIN:" input
done

while [[ "$input" != "$PICO_SO_PIN" ]]; do
    read -rp "Write down and enter the pico so pin again $PICO_SO_PIN:" input
done

read -p "Done! Press enter to reboot now (next script is post-init.sh)"

sudo raspi-config nonint do_overlayfs 1

source .env
sudo nmcli con modify $NMCLI_CON_NAME autoconnect on # TODO: check if this is persistent & why it timeouts sometimes

sudo reboot
