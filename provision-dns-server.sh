#!/bin/bash
set -eux

pandora_ip_address="${1:-10.1.0.2}"; shift || true
pandora_domain="${1:-pandora.example.test}"; shift || true
k8s_domain="$(echo -n "$pandora_domain" | sed -E 's,^[a-z0-9-]+\.(.+),\1,g')"
default_dns_resolver="$(systemd-resolve --status | awk '/DNS Servers: /{print $3}')" # recurse queries through the default vagrant environment DNS server.

#
# provision the DNS server/resolver/recursor.
# this will resolve all entries from /etc/hosts by default (like our $pandora_domain).
# and will redirect all *.$k8s_domain to the local pdns server.
# NB docker/coredns/kubernetes inherits resolv.conf from the host.
# see http://www.thekelleys.org.uk/dnsmasq/docs/setup.html
# see http://www.thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html

apt-get install -y --no-install-recommends dnsutils dnsmasq
systemctl stop systemd-resolved
systemctl disable systemd-resolved
cat >/etc/dnsmasq.d/local.conf <<EOF
no-resolv
bind-interfaces
interface=eth1
listen-address=$pandora_ip_address
# all *.$k8s_domain which arent in /etc/hosts are forward to our pdns server.
server=/$k8s_domain/127.0.0.2
server=$default_dns_resolver
EOF
rm /etc/resolv.conf
cat >/etc/resolv.conf <<EOF
nameserver 127.0.0.1
search $k8s_domain
EOF
systemctl restart dnsmasq

#
# provision the DNS authoritative server.
# NB this will be controlled by the kubernetes external dns controller.

# these anwsers were obtained (after installing pdns-backend-sqlite3) with:
#
#   #sudo debconf-show pdns-backend-sqlite3
#   sudo apt-get install debconf-utils
#   # this way you can see the comments:
#   sudo debconf-get-selections
#   # this way you can just see the values needed for debconf-set-selections:
#   sudo debconf-get-selections | grep -E '^pdns-.+\s+' | sort
debconf-set-selections<<EOF
pdns-backend-sqlite3 pdns-backend-sqlite3/dbconfig-install boolean true
EOF

apt-get install -y --no-install-recommends dnsutils pdns-backend-sqlite3

# stop pdns before changing the configuration.
systemctl stop pdns

function pdns-set-config {
    local key="$1"; shift
    local value="${1:-}"; shift || true
    sed -i -E "s,^(\s*#\s*)?($key\s*)=.*,\2=$value," /etc/powerdns/pdns.conf
}

# save the original config.
cp /etc/powerdns/pdns.conf{,.orig}
# listen at the localhost.
pdns-set-config local-address 127.0.0.2
# do not listen on ipv6.
pdns-set-config local-ipv6
# configure the api server.
pdns-set-config api yes
pdns-set-config api-key vagrant
pdns-set-config webserver-address "$pandora_ip_address"
pdns-set-config webserver-port 8081
pdns-set-config webserver-allow-from "$pandora_ip_address/24"
# increase the logging level.
# you can see the logs with journalctl --follow -u pdns
#pdns-set-config loglevel 10
#pdns-set-config log-dns-queries yes
# diff the changes.
diff -u /etc/powerdns/pdns.conf{.orig,} || true

# load the $k8s_domain zone into the database.
# NB we use 1m for testing purposes, in real world, this should probably be 10m+.
zone="
\$TTL 1m
\$ORIGIN $k8s_domain. ; base domain-name
@               IN      SOA     a.ns    hostmaster (
    2019090800 ; serial number (this number should be increased each time this zone file is changed)
    1m         ; refresh (the polling interval that slave DNS server will query the master for zone changes)
               ; NB the slave will use this value insted of \$TTL when deciding if the zone it outdated
    1m         ; update retry (the slave will retry a zone transfer after a transfer failure)
    3w         ; expire (the slave will ignore this zone if the transfer keeps failing for this long)
    1m         ; minimum (the slave stores negative results for this long)
)
                IN      NS      a.ns
"
# TODO add the reverse zone.
zone2sql --zone=<(echo "$zone") --gsqlite | sqlite3 /var/lib/powerdns/pdns.sqlite3

# start it up.
systemctl start pdns

# use the API.
# see https://doc.powerdns.com/authoritative/http-api
wget -qO- --header 'X-API-Key: vagrant' http://$pandora_ip_address:8081/api/v1/servers | jq .
wget -qO- --header 'X-API-Key: vagrant' http://$pandora_ip_address:8081/api/v1/servers/localhost/zones | jq .
wget -qO- --header 'X-API-Key: vagrant' http://$pandora_ip_address:8081/api/v1/servers/localhost/zones/$k8s_domain | jq .

# use the DNS resolver.
cat /etc/hosts
dig $pandora_domain
dig -x $pandora_ip_address
