#!/bin/bash
set -eux

dns_server_ip_address="${1:-10.1.0.2}"; shift || true

# change the dns resolver to use our dns server.
cat >/etc/netplan/01-netcfg.yaml <<EOF
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: yes
      dhcp4-overrides:
        use-dns: false
      nameservers:
        addresses:
          - $dns_server_ip_address
EOF
netplan apply

# wait for the configuration to be applied.
# NB RKE kubelet uses this file as --resolv-conf=/run/systemd/resolve/resolv.conf
while [ "$(awk '/^nameserver /{print $2}' /run/systemd/resolve/resolv.conf)" != "$dns_server_ip_address" ]; do
  sleep 1
done
cat /run/systemd/resolve/resolv.conf
