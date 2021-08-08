#!/bin/bash
source /vagrant/lib.sh

master_index="${1:-1}"; shift || true
apiserver_advertise_address=$1; shift || true
pod_network_cidr=$1; shift || true
service_cidr=$1; shift || true
service_dns_domain=$1; shift || true
kubernetes_version="${1:-1.22.0}"; shift || true
kubernetes_control_plane_endpoint="${1:-k8s.example.test:443}"; shift || true
kuberouter_version="${1:-v1.3.0}"; shift || true
kubernetes_dashboard_url="${1:-https://raw.githubusercontent.com/kubernetes/dashboard/v2.3.1/aio/deploy/recommended.yaml}"; shift || true

kuberouter_url="https://raw.githubusercontent.com/cloudnativelabs/kube-router/$kuberouter_version/daemonset/kubeadm-kuberouter-all-features.yaml"

if [ "$master_index" == '0' ]; then
# initialize kubernetes.
# see https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
# see https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
mkdir -p /vagrant/tmp
kubeadm init \
    --kubernetes-version=$kubernetes_version \
    --apiserver-advertise-address=$apiserver_advertise_address \
    --pod-network-cidr=$pod_network_cidr \
    --service-cidr=$service_cidr \
    --service-dns-domain=$service_dns_domain \
    --control-plane-endpoint=$kubernetes_control_plane_endpoint \
    --skip-phases=addon/kube-proxy \
    --upload-certs \
    | tee kubeadm-init.log

# save the kubeadm join command which will later be used to add
# the workers to the cluster. this token is valid for one day.
cat >/vagrant/tmp/kubeadm-join.sh <<EOF
$(kubeadm token create --print-join-command | tr '\n' ' ')
EOF

# save the kubeadm join command to join other master nodes.
#
# NB this is done by parsing kubeadm-init.log because I did not find other way to get this command line.
# NB kubeadm-init.log will contain something like:
#
#     Your Kubernetes control-plane has initialized successfully!
#
#     To start using your cluster, you need to run the following as a regular user:
#
#       mkdir -p $HOME/.kube
#       sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
#       sudo chown $(id -u):$(id -g) $HOME/.kube/config
#
#     You should now deploy a pod network to the cluster.
#     Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
#       https://kubernetes.io/docs/concepts/cluster-administration/addons/
#
#     You can now join any number of the control-plane node running the following command on each as root:
#
#       kubeadm join k8s.example.test:443 --token m25ixd.xoknbughtvuq3ytt \
#         --discovery-token-ca-cert-hash sha256:3908313059febef282c59492ff67641c0db5d7a181639f095ad796aa7256fc54 \
#         --control-plane --certificate-key afe7049ea72b444840f495b34ee21a3f876a868b7e52bdcedb857a28a3378019
#
#     Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
#     As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
#     "kubeadm init phase upload-certs --upload-certs" to reload certs afterward.
#
#     Then you can join any number of worker nodes by running the following on each as root:
#
#     kubeadm join k8s.example.test:443 --token m25ixd.xoknbughtvuq3ytt \
#         --discovery-token-ca-cert-hash sha256:3908313059febef282c59492ff67641c0db5d7a181639f095ad796aa7256fc54
#
#     configure kubectl in the root and vagrant accounts with kubernetes superuser privileges.
#
# the following python script will parse the kubeadm join --control-plane line.
python3 >/vagrant/tmp/kubeadm-join-control-plane.sh <<'EOF'
import re

kubeadm_join_begin_re = re.compile(r'^(kubeadm join .+?)\s*\\$')
kubeadm_join_continue_re = re.compile(r'^(--.+?)\s*\\?$')

def get_kubeadm_join_commands(path):
  command = []
  before_command = True
  for line in open(path):
    line = line.strip()
    if before_command:
      m = kubeadm_join_begin_re.match(line)
      if not m:
        continue
      command = [m.group(1)]
      before_command = False
    else:
      m = kubeadm_join_continue_re.match(line)
      if m:
        command_continuation = m.group(1)
        command.append(command_continuation)
        if not command_continuation.endswith(r'\\'):
          continue
      command.append('"$@"')
      yield " \\\n  ".join(command).strip()
      before_command = True

for command in get_kubeadm_join_commands('kubeadm-init.log'):
  if ' --control-plane ' in command:
    print(command)
EOF

# save the kubectl configuration.
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

# show the in-cluster kubeadm configuration.
kubectl get configmap -n kube-system kubeadm-config -o yaml

# create the kube-proxy configmap with the admin kubeconfig.
# NB this is required to workaround https://github.com/cloudnativelabs/kube-router/issues/859.
# NB this has a side-effect that shows an warning when joining a worker node:
#     W0808 11:59:38.772103    4853 configset.go:77] Warning: No kubeproxy.config.k8s.io/v1alpha1 config is loaded. Continuing without it: configmaps "kube-proxy" is forbidden: User "system:bootstrap:p16khe" cannot get resource "configmaps" in API group "" in the namespace "kube-system"
kubectl create configmap \
  -n kube-system \
  kube-proxy \
  --from-file=kubeconfig.conf=/etc/kubernetes/admin.conf

# install the kube-router cni addon as the cluster IPVS/LVS based Service proxy,
# Network Policy Controller (aka firewall) and Pod Networking.
# see https://github.com/cloudnativelabs/kube-router
# see https://github.com/cloudnativelabs/kube-router/blob/master/docs/kubeadm.md
wget -qO- "$kuberouter_url" \
  | sed -E s",(image:\s*.+/cloudnativelabs/kube-router)$,\1:$kuberouter_version,g" \
  >/vagrant/tmp/kube-router.yaml
kubectl apply -f /vagrant/tmp/kube-router.yaml

# wait for this node to be Ready.
# e.g. km1     Ready     master    35m       v1.22.0
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
else
# join the cluster as a master.
bash /vagrant/tmp/kubeadm-join-control-plane.sh \
    --apiserver-advertise-address=$apiserver_advertise_address \
    | tee kubeadm-join.log

# save the kubectl configuration.
for home in /root /home/vagrant; do
    o=$(stat -c '%U' $home)
    g=$(stat -c '%G' $home)
    install -d -m 700 -o $o -g $g $home/.kube
    install -m 600 -o $o -g $g /etc/kubernetes/admin.conf $home/.kube/config
done
fi

# show the etcd nodes.
etcdctl \
    --cert /etc/kubernetes/pki/etcd/server.crt \
    --key /etc/kubernetes/pki/etcd/server.key \
    --cacert /etc/kubernetes/pki/etcd/ca.crt \
    --write-out table \
    member list

# show the etcd endpoint status.
etcdctl \
    --cert /etc/kubernetes/pki/etcd/server.crt \
    --key /etc/kubernetes/pki/etcd/server.key \
    --cacert /etc/kubernetes/pki/etcd/ca.crt \
    --write-out table \
    endpoint status

# list all nodes and pods.
kubectl get nodes -o wide
kubectl get pods -o wide --all-namespaces

# kubernetes info.
kubectl version --short
kubectl cluster-info
crictl info
kubectl get all --all-namespaces
crictl ps

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
for ns in $(ctr namespaces list -q); do ctr -n $ns container list | xargs -L1 -I% echo "$ns %"; done
