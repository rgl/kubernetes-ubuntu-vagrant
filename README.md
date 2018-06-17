This is a kubeadm created kubernetes playground wrapped in a vagrant environment.

# Usage

Install the [Ubuntu Base Box](https://github.com/rgl/ubuntu-vagrant).

Launch a master and a worker:

```bash
vagrant up k8s-1 k8s-2
export KUBECONFIG=$PWD/tmp/admin.conf
```

Launch the kubernetes api server proxy in background:

```bash
kubectl proxy &
```

Then access the kubernetes dashboard at:

    http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/

and click `Skip` to login (this works because we granted admin privileges to the dashboard service account).
