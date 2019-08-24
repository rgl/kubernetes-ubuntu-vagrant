#!/bin/bash
set -eux

apiserver_advertise_address=$1; shift || true
pod_network_cidr=$1; shift || true
service_cidr=$1; shift || true
service_dns_domain=$1; shift || true
kubernetes_version="${1:-1.15.3}"; shift || true
kuberouter_url="${1:-https://raw.githubusercontent.com/cloudnativelabs/kube-router/v0.3.2/daemonset/kubeadm-kuberouter.yaml}"; shift || true
kubernetes_dashboard_url="${1:-https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta3/aio/deploy/recommended.yaml}"; shift || true

# initialize kubernetes.
# TODO add --skip-phases=addon/kube-proxy and use kuberouter instead OR use kube-proxy IPVS mode?
mkdir -p /vagrant/tmp
kubeadm init \
    --kubernetes-version=$kubernetes_version \
    --apiserver-advertise-address=$apiserver_advertise_address \
    --pod-network-cidr=$pod_network_cidr \
    --service-cidr=$service_cidr \
    --service-dns-domain=$service_dns_domain
# save the kubeadm join command which will later be used to add
# the workers to the cluster. this token is valid for one day.
kubeadm token create --print-join-command >/vagrant/tmp/kubeadm-join.sh

# configure kubectl in the root and vagrant accounts with kubernetes superuser privileges.
for home in /root /home/vagrant; do
    o=$(stat -c '%U' $home)
    g=$(stat -c '%G' $home)
    install -d -m 700 -o $o -g $g $home/.kube
    install -m 600 -o $o -g $g /etc/kubernetes/admin.conf $home/.kube/config
done

# also save the kubectl configuration on the host, so we can access it there.
cp /etc/kubernetes/admin.conf /vagrant/tmp

# uncomment the next line if you want let the master node run user pods (not recommended).
#kubectl taint nodes --all node-role.kubernetes.io/master-

# install the kube-router cni addon as the pod network driver.
# see https://github.com/cloudnativelabs/kube-router
# see https://github.com/cloudnativelabs/kube-router/blob/master/Documentation/kubeadm.md
kubectl apply -f "$kuberouter_url"

# wait for this node to be Ready.
# e.g. km1     Ready     master    35m       v1.15.3
$SHELL -c 'node_name=$(hostname); while [ -z "$(kubectl get nodes $node_name | grep -E "$node_name\s+Ready\s+")" ]; do sleep 3; done'

# wait for the kube-dns pod to be Running.
# e.g. coredns-fb8b8dccf-rh4fg   1/1     Running   0          33m
$SHELL -c 'while [ -z "$(kubectl get pods --selector k8s-app=kube-dns --namespace kube-system | grep -E "\s+Running\s+")" ]; do sleep 3; done'

# install the kubernetes dashboard.
# see https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
kubectl apply -f "$kubernetes_dashboard_url"

# create the admin user.
# see https://github.com/kubernetes/dashboard/wiki/Creating-sample-user
# see https://github.com/kubernetes/dashboard/wiki/Access-control
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: admin
    namespace: kube-system
EOF
# save the admin token.
kubectl \
  -n kube-system \
  get \
  secret \
  $(kubectl -n kube-system get secret | grep admin-token- | awk '{print $1}') \
  -o json | jq -r .data.token | base64 --decode \
  >/vagrant/tmp/admin-token.txt

# list all nodes and pods.
kubectl get nodes -o wide
kubectl get pods --all-namespaces

# kubernetes info.
kubectl version --short
kubectl cluster-info
#kubectl get nodes -o wide
#kubectl get pods --all-namespaces
kubectl get all --all-namespaces

# rbac info.
kubectl get serviceaccount --all-namespaces
kubectl get role --all-namespaces
kubectl get rolebinding --all-namespaces
kubectl get rolebinding --all-namespaces -o json | jq .items[].subjects
kubectl get clusterrole --all-namespaces
kubectl get clusterrolebinding --all-namespaces

# list bootstrap tokens.
kubeadm token list

# list system secrets.
kubectl -n kube-system get secret

# list services.
kubectl get svc

# list the kubernetes configuration files.
find /etc/kubernetes

# show listening ports.
ss -n --tcp --listening --processes

# show network routes.
ip route

# show running containers.
docker ps --format '{{.Image}} {{.Command}}' --no-trunc
for ns in $(ctr namespaces list -q); do ctr -n $ns container list | xargs -L1 -I% echo "$ns %"; done
