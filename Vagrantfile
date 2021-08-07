# to make sure the km1 node is created before the other nodes, we
# have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

require 'ipaddr'

docker_version = '5:19.03.2~3-0~ubuntu-bionic' # NB execute apt-cache madison docker-ce to known the available versions.
kubernetes_version = '1.16.0'
kubeadm_version = "#{kubernetes_version}-00" # NB execute apt-cache madison kubeadm to known the available versions.
kubelet_version = "#{kubernetes_version}-00" # NB execute apt-cache madison kubelet to known the available versions.
kubectl_version = "#{kubernetes_version}-00" # NB execute apt-cache madison kubectl to known the available versions.
kuberouter_url = 'https://raw.githubusercontent.com/cloudnativelabs/kube-router/d6f9f31a7b8075fad418517860fede7a53adf7b6/daemonset/kubeadm-kuberouter.yaml'
kubernetes_dashboard_url = 'https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta4/aio/deploy/recommended.yaml'

number_of_master_nodes = 3
number_of_worker_nodes = 2
first_master_node_ip  = '10.11.0.101'
first_worker_node_ip  = '10.11.0.201'
pod_network_cidr      = '10.12.0.0/16'
service_cidr          = '10.13.0.0/16'  # default is 10.96.0.0/12
service_dns_domain    = 'example.test'  # default is cluster.local
master_node_ip_addr = IPAddr.new first_master_node_ip
worker_node_ip_addr = IPAddr.new first_worker_node_ip

pandora_fqdn                          = 'pandora.example.test'
pandora_ip_address                    = '10.11.0.2'
kubernetes_control_plane_fqdn         = 'k8s.example.test'
kubernetes_control_plane_endpoint     = "#{kubernetes_control_plane_fqdn}:443"
kubernetes_control_plane_ip_address   = '10.11.0.3'

hosts = """
127.0.0.1	localhost
#{pandora_ip_address} #{pandora_fqdn}
#{kubernetes_control_plane_ip_address} #{kubernetes_control_plane_fqdn}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
"""

Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu-20.04-amd64'

  config.vm.provider 'libvirt' do |lv, config|
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    #lv.nested = true
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs'
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.linked_clone = true
    vb.cpus = 4
  end

  config.vm.define :pandora do |config|
    config.vm.provider 'libvirt' do |lv, config|
      lv.memory = 1*1024
    end
    config.vm.provider 'virtualbox' do |vb|
      vb.memory = 1*1024
    end
    config.vm.hostname = pandora_fqdn
    config.vm.network :private_network, ip: pandora_ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
    config.vm.network :private_network, ip: kubernetes_control_plane_ip_address, libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
    config.vm.provision 'shell', inline: 'echo "$1" >/etc/hosts', args: [hosts]
    config.vm.provision 'shell', path: 'provision-base.sh'
    config.vm.provision 'shell', path: 'provision-dns-server.sh', args: [pandora_ip_address, pandora_fqdn]
    config.vm.provision 'shell', path: 'provision-docker.sh', args: [docker_version]
    config.vm.provision 'shell', path: 'provision-haproxy.sh', args: [kubernetes_control_plane_ip_address, kubernetes_control_plane_fqdn]
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
      config.vm.provision 'shell', path: 'provision-dns-client.sh', args: [pandora_ip_address]
      config.vm.provision 'shell', path: 'provision-docker.sh', args: [docker_version]
      config.vm.provision 'shell', path: 'provision-kubernetes-tools.sh', args: [
        ip,
        kubeadm_version,
        kubelet_version,
        kubectl_version,
      ]
      config.vm.provision 'shell', path: 'provision-kubernetes-master.sh', args: [
        n-1,
        ip,
        pod_network_cidr,
        service_cidr,
        service_dns_domain,
        kubernetes_version,
        kubernetes_control_plane_endpoint,
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
      config.vm.provision 'shell', path: 'provision-dns-client.sh', args: [pandora_ip_address]
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
