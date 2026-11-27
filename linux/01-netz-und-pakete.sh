#!/usr/bin/env bash
# LNX01: feste IP, DNS auf DC01, Zeit vom DC, Pakete fuer Samba-Domaenenmitglied und Docker
set -euo pipefail
IP=10.10.10.20
DC=10.10.10.10
IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)

cat > /etc/netplan/50-lab.yaml <<NETPLAN
network:
  version: 2
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [${IP}/24]
      routes:
        - to: default
          via: 10.10.10.1
      nameservers:
        search: [lab.local]
        addresses: [${DC}]
NETPLAN
chmod 600 /etc/netplan/50-lab.yaml
rm -f /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml
netplan apply

hostnamectl set-hostname lnx01
sed -i '/lnx01/d' /etc/hosts && sed -i "1i ${IP} lnx01.lab.local lnx01" /etc/hosts
echo 'manage_etc_hosts: false' > /etc/cloud/cloud.cfg.d/99-hosts.cfg

timedatectl set-timezone Europe/Vienna
sed -i 's/^#\?NTP=.*/NTP=dc01.lab.local/' /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -yq samba winbind libnss-winbind libpam-winbind krb5-user acl docker.io docker-compose-v2
systemctl enable --now docker
echo "fertig: $(hostname -f) $(ip -4 -o addr show ${IFACE} | awk '{print $4}')"
