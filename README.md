This is a kubeadm created kubernetes playground wrapped in a vagrant environment.

# Usage

Install the [Ubuntu Base Box](https://github.com/rgl/ubuntu-vagrant).

Install kublectl in your machine, e.g. on Ubuntu:

```bash
wget -qO /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo 'deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' >/etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubectl
kubectl version --client
```

Launch the pandora box, a kubernetes master (`km1`) and a worker (`kw1`):

```bash
vagrant up pandora km1 kw1
```

Add the following entries to your `/etc/hosts` file:

```plain
10.11.0.3 k8s.example.test
```

Access the HAProxy status page at:

http://k8s.example.test:9000

# Kubernetes proxy

Launch the kubernetes api server proxy in background:

```bash
export KUBECONFIG=$PWD/tmp/admin.conf
kubectl proxy &
```

Then access the kubernetes dashboard at:

    http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

select `Token` and use the token from the `tmp/admin-token.txt` file.

# Kubernetes Basics Condensed Tutorial

**NB** See the full [Kubernetes Basics tutorial](https://kubernetes.io/docs/tutorials/kubernetes-basics/).

Install httpie:

```bash
apt-get install -y httpie
```

Launch an example Deployment and wait for it to be up:

```bash
kubectl create deployment kubernetes-bootcamp --image=gcr.io/google-samples/kubernetes-bootcamp:v1
kubectl get deployments
kubectl rollout status deployment kubernetes-bootcamp
```

Access it by http through the kubernetes proxy:

```bash
export POD_NAME=$(kubectl get pods -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep kubernetes-bootcamp)
echo "Name of the Pod: $POD_NAME"
# get the pod definition:
http http://localhost:8001/api/v1/namespaces/default/pods/$POD_NAME
# access the pod http endpoint at port 8080:
http http://localhost:8001/api/v1/namespaces/default/pods/$POD_NAME:8080/proxy/
```

Execute a command inside the pod:

```bash
kubectl exec $POD_NAME -- env
kubectl exec $POD_NAME -- curl --verbose --silent localhost:8080
```

Launch an interactive shell inside the pod:

```bash
kubectl exec -ti $POD_NAME -- bash
```

Show information about the pod:

```bash
kubectl describe pod $POD_NAME
```

Expose the pod as a kubernetes Service that can be accessed at any kubernetes node:

```bash
kubectl expose deployment kubernetes-bootcamp --type NodePort --port 8080
kubectl get services
kubectl describe service kubernetes-bootcamp
```

Access the Service through the `kw1` worker node:

```bash
export NODE_PORT=$(kubectl get service kubernetes-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}')
echo NODE_PORT=$NODE_PORT
http http://10.11.0.201:$NODE_PORT
```

You can also access the service trought the `kubectl proxy` proxy:

```bash
http http://localhost:8001/api/v1/namespaces/default/services/kubernetes-bootcamp:8080/proxy/
```

Create multiple instances (aka replicas) of the application:

```bash
kubectl scale deployments/kubernetes-bootcamp --replicas=4
kubectl rollout status deployment kubernetes-bootcamp
kubectl get deployments
kubectl get pods -o wide
kubectl describe deployment kubernetes-bootcamp
kubectl describe service kubernetes-bootcamp
kubectl get endpoints kubernetes-bootcamp -o yaml
```

And access the Service multiple times to see the request being handled by different containers:

```bash
http http://10.11.0.201:$NODE_PORT
http http://10.11.0.201:$NODE_PORT
http http://10.11.0.201:$NODE_PORT
```

Upgrade the application version:

```bash
kubectl set image deployment kubernetes-bootcamp kubernetes-bootcamp=jocatalin/kubernetes-bootcamp:v2
kubectl rollout status deployment kubernetes-bootcamp # wait for rollout.
kubectl describe pods # see the image.
http http://10.11.0.201:$NODE_PORT # hit it again, now to see v=2.
```

Remove the application:

```bash
kubectl delete deployment kubernetes-bootcamp
kubectl delete service kubernetes-bootcamp
kubectl get all
```
