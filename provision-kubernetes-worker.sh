#!/bin/bash
set -eux

# join the node to the existing kubernetes cluster.
# e.g. kubeadm join --token afc06d.c28d47adaa49de75 10.11.0.101:6443 --discovery-token-ca-cert-hash sha256:263a4babbdf9aae8d6e8e0d394c613eeb25b65c670fadef1814c1a735823d16f
$SHELL -x /vagrant/tmp/kubeadm-join.sh
