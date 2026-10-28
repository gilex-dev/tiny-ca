#!/bin/bash
cd "$(dirname "${BASH_SOURCE[0]}")" && cd ..
# all paths relative to project root from here

read -p "Put the pico into flash mode now (hold the BOOT button while pressing RESET). Then press enter"
sleep 4 && lsblk
read -rp "Enter the path to the pico's partition (e.g. /dev/sdb1):" PICO_PART_PATH

NMCLI_CON_NAME=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active | awk -F: '$3 != "lo" {print $1;}')

sudo useradd step
sudo passwd -l step

sudo apt update
sudo apt install -y opensc cryptsetup pwgen btrfs-progs python3-usb overlayroot jq
sudo mv bin/step-ca /usr/local/bin/
sudo mv bin/step-kms-plugin /usr/local/bin/
wget https://github.com/smallstep/cli/releases/download/v0.31.0/step-cli_armv6.deb -O bin/step-cli.deb
echo "47876127b421021983325ceaaf9c543990bd2f391fb058fae2907d42ea01132b bin/step-cli.deb" >checksums.txt
sha256sum -c checksums.txt && sudo dpkg -i bin/step-cli.deb
wget https://github.com/polhenarejos/pico-hsm/releases/download/v6.6/pico_hsm_pico2-6.6.uf2 -O bin/pico_hsm_pico2.uf2
echo "7c3cc9d3208888013964dde6a51a5911fe38961e503eca5289261662917f96bf bin/pico_hsm_pico2.uf2" >checksums.txt
wget https://github.com/polhenarejos/pico-rng/raw/refs/tags/v1.0/firmware/pico_rng_test.py

sudo mkdir -p /mnt/pico
sudo mount $PICO_PART_PATH /mnt/pico
sudo cp bin/pico_rng.uf2 /mnt/pico
sudo umount /mnt/pico

read -p "Reset the pico (press the RESET button). Then press enter"

echo "Generate and store HSM PIN in env file"
sudo insmod bin/pico_rng.ko && sleep 5

echo "Check, check. Is this thing on?"
sudo timeout 5 python pico_rng_test.py --performance

sudo mkdir -p /etc/step-ca
sudo su -c "echo $(pwgen -s 15 1) > /etc/step-ca/hsm-pin.txt"
sudo rmmod pico-rng

# Prepare system for Pico-HSM
sudo cp /usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist /usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist.bak

HSM_PRODUCT_ID=10fd
HSM_VENDOR_ID=2e8a

# TODO: indentation not working with double quotes "
sudo sed -i "/^[[:space:]]*<key>ifdVendorID<\/key>/{n; a\
                <string>0x$HSM_VENDOR_ID</string>
}" /usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist
sudo sed -i "/^[[:space:]]*<key>ifdProductID<\/key>/{n; a\
                <string>0x$HSM_PRODUCT_ID</string>
}" /usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist
sudo sed -i '/^[[:space:]]*<key>ifdFriendlyName<\/key>/{n; a\
                <string>Pol Henarejos Pico Key</string>
}' /usr/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist

sudo tee /etc/udev/rules.d/75-pico-hsm.rules >/dev/null <<EOF
SUBSYSTEM=="usb", ATTRS{idVendor}=="$HSM_VENDOR_ID", ATTRS{idProduct}=="$HSM_PRODUCT_ID", MODE="0666"
EOF

sudo udevadm control --reload-rules

echo "export NMCLI_CON_NAME=$NMCLI_CON_NAME" >.env
sudo cp templates/50-step-pcsc.rules /etc/polkit-1/rules.d/
# sudo systemctl restart polkit
# sudo systemctl restart pcscd

sudo nmcli connection modify $NMCLI_CON_NAME autoconnect off # TODO: check why it timeouts sometimes

read -p "Done! Press enter to reboot now or exit with CTRL+C (next script is init.sh)"

sudo raspi-config nonint do_overlayfs 0
sudo reboot
