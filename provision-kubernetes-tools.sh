#!/bin/bash
set -eux

# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# install kubernetes tools.
# see https://kubernetes.io/docs/setup/independent/install-kubeadm/
wget -qO- https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
add-apt-repository "deb http://apt.kubernetes.io/ kubernetes-$(lsb_release -cs) main"
apt-get update
apt-get install -y kubelet kubeadm kubectl

# make sure kublet uses the same cgroup driver as docker.
docker_cgroup_driver=$(docker info -f '{{.CgroupDriver}}')
cat >/etc/systemd/system/kubelet.service.d/11-cgroup-driver.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=$docker_cgroup_driver"
EOF
systemctl daemon-reload
systemctl restart kubelet

# kick the tires.
kubelet --version
kubeadm version -o json
kubectl version -o json 2>/dev/null || true
