#!/usr/bin/env bash
# LNX01 als Mitglied der Domaene lab.local (Samba + Winbind), Abteilungsfreigaben mit AD-Gruppen
# Aufruf: sudo ./02-samba-domaenenmitglied.sh   (fragt einmal nach dem Passwort von LAB\Administrator)
set -euo pipefail
ABTEILUNGEN=(Geschaeftsfuehrung IT Vertrieb Buchhaltung Technik)
BASIS=/srv/freigaben

cat > /etc/krb5.conf <<KRB
[libdefaults]
    default_realm = LAB.LOCAL
    dns_lookup_realm = false
    dns_lookup_kdc = true
KRB

{
cat <<SMB
[global]
    workgroup = LAB
    realm = LAB.LOCAL
    security = ads
    netbios name = LNX01
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config LAB : backend = rid
    idmap config LAB : range = 10000-999999
    winbind use default domain = yes
    winbind enum users = no
    winbind enum groups = no
    template shell = /bin/bash
    template homedir = /home/%U
    vfs objects = acl_xattr
    map acl inherit = yes
    store dos attributes = yes
    server min protocol = SMB2_10
    log file = /var/log/samba/log.%m
    max log size = 1000
SMB
for A in "${ABTEILUNGEN[@]}"; do
cat <<SHARE

[${A}]
    path = ${BASIS}/${A}
    read only = no
    valid users = @"LAB\DL_Share_${A}_RW" @"LAB\DL_Share_${A}_R" @"LAB\Domain Admins"
    write list = @"LAB\DL_Share_${A}_RW" @"LAB\Domain Admins"
    access based share enum = yes
SHARE
done
} > /etc/samba/smb.conf
testparm -s >/dev/null

net ads join -U Administrator
sed -i 's/^passwd:.*/passwd:         files systemd winbind/; s/^group:.*/group:          files systemd winbind/' /etc/nsswitch.conf
systemctl enable --now winbind smbd nmbd
systemctl restart winbind smbd

for A in "${ABTEILUNGEN[@]}"; do
    mkdir -p "${BASIS}/${A}"
    chown root:"domain admins" "${BASIS}/${A}"
    chmod 2770 "${BASIS}/${A}"
    setfacl -m g:"dl_share_${A,,}_rw":rwx -m d:g:"dl_share_${A,,}_rw":rwx \
            -m g:"dl_share_${A,,}_r":rx   -m d:g:"dl_share_${A,,}_r":rx "${BASIS}/${A}"
done

wbinfo -t
wbinfo -g | grep -i dl_share
smbclient -L localhost -N 2>/dev/null | grep Disk || true
