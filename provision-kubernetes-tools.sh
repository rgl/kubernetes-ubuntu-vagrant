#!/bin/bash
set -eux

node_ip=$1

# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# install kubernetes tools.
# see https://kubernetes.io/docs/setup/independent/install-kubeadm/
# NB even thou we are on ubuntu bionic (18.04) we are using the xenial packages
#    because they are the only available packages and are compatible with bionic.
wget -qO- https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
add-apt-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
apt-get update
apt-get install -y kubelet kubeadm kubectl

# make sure kublet uses:
#   1. the same cgroup driver as docker.
#   2. the correct node-ip address.
#       NB in vagrant the first interface is for NAT but we want to use the
#          second interface for the kubernetes control plane.
#       NB this is seen in the INTERNAL-IP column of the kubectl get nodes -o wide output.
docker_cgroup_driver=$(docker info -f '{{.CgroupDriver}}')
cat >/etc/systemd/system/kubelet.service.d/11-cgroup-driver.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=$docker_cgroup_driver"
EOF
cat >/etc/systemd/system/kubelet.service.d/11-node-ip.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--node-ip=$node_ip"
EOF
systemctl daemon-reload
systemctl restart kubelet
systemctl cat kubelet.service

# kick the tires.
kubelet --version
kubeadm version -o json
kubectl version -o json 2>/dev/null || true
