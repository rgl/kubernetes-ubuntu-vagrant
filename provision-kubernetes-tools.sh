#!/bin/bash
source /vagrant/lib.sh

node_ip=$1; shift || true
kubeadm_version="${1:-1.22.0}"; shift || true # NB execute apt-cache madison kubeadm to known the available versions.
kubelet_version="${1:-1.22.0}"; shift || true # NB execute apt-cache madison kubelet to known the available versions.
kubectl_version="${1:-1.22.0}"; shift || true # NB execute apt-cache madison kubectl to known the available versions.

# prevent apt-get et al from asking questions.
# NB even with this, you'll still get some warnings that you can ignore:
#     dpkg-preconfigure: unable to re-open stdin: No such file or directory
export DEBIAN_FRONTEND=noninteractive

# install kubernetes tools.
# see https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management
# see https://kubernetes.io/docs/setup/independent/install-kubeadm/
# NB even thou we are on ubuntu focal (20.04) we are using the xenial packages
#    because they are the only available packages and are compatible with bionic.
wget -qO /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo 'deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' >/etc/apt/sources.list.d/kubernetes.list
apt-get update
kubeadm_package_version="$(apt-cache madison kubeadm | awk "/$kubeadm_version-/{print \$3}")"
kubelet_package_version="$(apt-cache madison kubelet | awk "/$kubelet_version-/{print \$3}")"
kubectl_package_version="$(apt-cache madison kubectl | awk "/$kubectl_version-/{print \$3}")"
apt-get install -y "kubeadm=$kubeadm_package_version" "kubelet=$kubelet_package_version" "kubectl=$kubectl_package_version"
apt-mark hold kubeadm kubelet kubectl

# make sure kublet uses:
#   1. the systemd cgroup driver.
#   2. the correct node-ip address.
#       NB in vagrant the first interface is for NAT but we want to use the
#          second interface for the kubernetes control plane.
#       NB this is seen in the INTERNAL-IP column of the kubectl get nodes -o wide output.
cat >/etc/systemd/system/kubelet.service.d/11-cgroup-driver.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=systemd"
EOF
cat >/etc/systemd/system/kubelet.service.d/11-node-ip.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--node-ip=$node_ip"
EOF
systemctl daemon-reload
systemctl restart kubelet
systemctl cat kubelet.service

# configure cri-tools to use containerd.
cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
#timeout: 2
#debug: true
#pull-image-on-create: false
EOF

# kick the tires.
kubelet --version
kubeadm version -o json
kubectl version -o json 2>/dev/null || true
