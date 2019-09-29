#!/bin/bash
set -eux

# join the node to the existing kubernetes cluster.
# e.g. kubeadm join k8s.example.test:443 --token kkppme.pprzxihtgjefg4vd --discovery-token-ca-cert-hash sha256:3908313059febef282c59492ff67641c0db5d7a181639f095ad796aa7256fc54
. /vagrant/tmp/kubeadm-join.sh
