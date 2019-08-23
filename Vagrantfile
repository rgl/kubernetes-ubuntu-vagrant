# to make sure the k8s-1 node is created before the other nodes, we
# have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

require 'ipaddr'

docker_version = '5:18.09.4~3-0~ubuntu-bionic' # NB execute apt-cache madison docker-ce to known the available versions.
kubernetes_version = '1.14.0'
kubeadm_version = "#{kubernetes_version}-00" # NB execute apt-cache madison kubeadm to known the available versions.
kubelet_version = "#{kubernetes_version}-00" # NB execute apt-cache madison kubelet to known the available versions.
kubectl_version = "#{kubernetes_version}-00" # NB execute apt-cache madison kubectl to known the available versions.
kuberouter_url = 'https://raw.githubusercontent.com/cloudnativelabs/kube-router/v0.3.2/daemonset/kubeadm-kuberouter.yaml'
kubernetes_dashboard_url = 'https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml'

number_of_master_nodes = 1
number_of_worker_nodes = 2
first_master_node_ip  = '10.11.0.101'
first_worker_node_ip  = '10.11.0.201'
pod_network_cidr      = '10.12.0.0/16'
service_cidr          = '10.13.0.0/16'  # default is 10.96.0.0/12
service_dns_domain    = 'vagrant.local' # default is cluster.local
master_node_ip_addr = IPAddr.new first_master_node_ip
worker_node_ip_addr = IPAddr.new first_worker_node_ip

Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu-18.04-amd64'

  config.vm.provider 'libvirt' do |lv, config|
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    lv.nested = true
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs'
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.linked_clone = true
    vb.cpus = 4
  end

  (1..number_of_master_nodes).each do |n|
    name = "km#{n}"
    fqdn = "#{name}.example.test"
    ip = master_node_ip_addr.to_s; master_node_ip_addr = master_node_ip_addr.succ

    config.vm.define name do |config|
      # NB 512M of memory is not enough to run a kubernetes master.
      config.vm.provider 'libvirt' do |lv, config|
        lv.memory = 1024
      end
      config.vm.provider 'virtualbox' do |vb|
        vb.memory = 1024
      end
      config.vm.hostname = fqdn
      config.vm.network :private_network, ip: ip, libvirt__forward_mode: 'none', libvirt__dhcp_enabled: false
      config.vm.provision 'shell', path: 'provision-base.sh', args: ['master']
      config.vm.provision 'shell', path: 'provision-docker.sh', args: [docker_version]
      config.vm.provision 'shell', path: 'provision-kubernetes-tools.sh', args: [
        ip,
        kubeadm_version,
        kubelet_version,
        kubectl_version,
      ]
      config.vm.provision 'shell', path: 'provision-kubernetes-master.sh', args: [
        ip,
        pod_network_cidr,
        service_cidr,
        service_dns_domain,
        kubernetes_version,
        kuberouter_url,
        kubernetes_dashboard_url,
      ]
    end
  end

  (1..number_of_worker_nodes).each do |n|
    name = "kw#{n}"
    fqdn = "#{name}.example.test"
    ip = worker_node_ip_addr.to_s; worker_node_ip_addr = worker_node_ip_addr.succ

    config.vm.define name do |config|
      config.vm.provider 'libvirt' do |lv, config|
        lv.memory = 2*1024
      end
      config.vm.provider 'virtualbox' do |vb|
        vb.memory = 2*1024
      end
      config.vm.hostname = fqdn
      config.vm.network :private_network, ip: ip, libvirt__forward_mode: 'none', libvirt__dhcp_enabled: false
      config.vm.provision 'shell', path: 'provision-base.sh', args: ['worker']
      config.vm.provision 'shell', path: 'provision-docker.sh', args: [docker_version]
      config.vm.provision 'shell', path: 'provision-kubernetes-tools.sh', args: [
        ip,
        kubeadm_version,
        kubelet_version,
        kubectl_version,
      ]
      config.vm.provision 'shell', path: 'provision-kubernetes-worker.sh'
    end
  end
end
