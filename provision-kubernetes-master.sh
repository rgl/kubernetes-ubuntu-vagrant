#!/bin/bash
set -eux

apiserver_advertise_address=$1
pod_network_cidr=$2

# initialize kubernetes.
# NB this also saves the kubeadm init output as it has the kubeadm join line
#    which will later be used to add the workers to the cluster.
mkdir -p /vagrant/tmp
kubeadm init \
    --apiserver-advertise-address=$apiserver_advertise_address \
    --pod-network-cidr=$pod_network_cidr \
    | tee /vagrant/tmp/kubeadm-init.log

# configure kubectl in the root and vagrant accounts with kubernetes superuser privileges.
for home in /root /home/vagrant; do
    o=$(stat -c '%U' $home)
    g=$(stat -c '%G' $home)
    install -d -m 700 -o $o -g $g $home/.kube
    install -m 600 -o $o -g $g /etc/kubernetes/admin.conf $home/.kube/config
done

# also save the kubectl configuration on the host, so we can access it there.
cp /etc/kubernetes/admin.conf /vagrant/tmp

# install the kube-router cni addon as the pod network driver.
# see https://github.com/cloudnativelabs/kube-router
# see https://github.com/cloudnativelabs/kube-router/blob/master/Documentation/kubeadm.md
wget -q https://raw.githubusercontent.com/cloudnativelabs/kube-router/master/daemonset/kubeadm-kuberouter.yaml
kubectl apply -f kubeadm-kuberouter.yaml

# wait for this node to be Ready.
# e.g. k8s-1     Ready     master    35m       v1.9.4
$SHELL -c 'node_name=$(hostname); while [ -z "$(kubectl get nodes $node_name | grep -E "$node_name\s+Ready\s+")" ]; do sleep 3; done'

# wait for the kube-dns pod to be Running.
# e.g. kube-dns-6f4fd4bdf-ggzn6   3/3       Running   0          33m
$SHELL -c 'while [ -z "$(kubectl get pods --selector k8s-app=kube-dns --namespace kube-system | grep -E "\s+Running\s+")" ]; do sleep 3; done'

# install the kubernetes dashboard.
# see https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/
wget -q https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
kubectl apply -f kubernetes-dashboard.yaml

# grant admin privileges to the dashboard service account.
# see https://github.com/kubernetes/dashboard/wiki/Access-control
kubectl apply -f <(echo '
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: kubernetes-dashboard
  labels:
    k8s-app: kubernetes-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: kubernetes-dashboard
  namespace: kube-system
')

# list all nodes and pods.
kubectl get nodes -o wide
kubectl get pods --all-namespaces

# show cluster-info.
kubectl cluster-info

# let the master node run user pods.
kubectl taint nodes --all node-role.kubernetes.io/master-

# list bootstrap tokens.
kubeadm token list

# list system secrets.
kubectl -n kube-system get secret

# list the kubernetes configuration files.
find /etc/kubernetes

# show listening ports.
netstat -anp | grep LISTEN

# show network routes.
ip route

# show running containers.
docker ps --format '{{.Image}} {{.Command}}' --no-trunc
