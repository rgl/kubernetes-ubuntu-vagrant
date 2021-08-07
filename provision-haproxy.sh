#!/bin/bash
set -eux

kubernetes_control_plane_ip_address="${1:-10.11.0.3}"; shift || true
kubernetes_control_plane_fqdn="${1:-k8s.example.test}"; shift || true
kubernetes_master_node_ip_addresses="${1:-10.11.0.101,10.11.0.102,10.11.0.103}"; shift || true

# install and configure haproxy as L4 TCP forwarding load balancer.
# see https://cbonte.github.io/haproxy-dconv/2.0/configuration.html#4-option%20httpchk
apt-get install -y haproxy
haproxy -vv
mv /etc/haproxy/haproxy.cfg{,.ubuntu}
cat >/etc/haproxy/haproxy.cfg <<EOF
global
  log /dev/log local0
  log /dev/log local1 notice
  chroot /var/lib/haproxy
  stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
  stats timeout 30s
  user haproxy
  group haproxy
  daemon

defaults
  log     global
  mode    http
  option  httplog
  option  dontlognull
  timeout connect 5000
  timeout client  50000
  timeout server  50000
  errorfile 400 /etc/haproxy/errors/400.http
  errorfile 403 /etc/haproxy/errors/403.http
  errorfile 408 /etc/haproxy/errors/408.http
  errorfile 500 /etc/haproxy/errors/500.http
  errorfile 502 /etc/haproxy/errors/502.http
  errorfile 503 /etc/haproxy/errors/503.http
  errorfile 504 /etc/haproxy/errors/504.http

defaults
  mode tcp
  timeout client 20s
  timeout server 20s
  timeout connect 4s

listen stats
  bind $kubernetes_control_plane_ip_address:9000
  mode http
  stats enable
  stats uri /

listen k8s
  bind $kubernetes_control_plane_ip_address:443 name k8s
  option tcplog
  log global
  option tcp-check
  timeout server 1h
  balance roundrobin
  default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
EOF
(
  i=0
  for ip_address in `echo "$kubernetes_master_node_ip_addresses" | tr , ' '`; do
    ((i=i+1))
    echo "  server km$i $ip_address:6443 check"
  done
)>>/etc/haproxy/haproxy.cfg

# restart to apply changes.
systemctl restart haproxy

# show current statistics.
# NB this is also available at $kubernetes_control_plane_ip_address:9000.
echo 'show stat' | nc -U /run/haproxy/admin.sock
