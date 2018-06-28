# to make sure the k8s-1 node is created before the other nodes, we
# have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

require 'ipaddr'

number_of_nodes  = 3
first_node_ip    = '10.11.0.201'
pod_network_cidr = '10.12.0.0/16'
node_ip_addr = IPAddr.new first_node_ip

Vagrant.configure(2) do |config|
  config.vm.box = 'ubuntu-16.04-amd64'

  config.vm.provider 'libvirt' do |lv, config|
    lv.memory = 2*1024
    lv.cpus = 4
    lv.cpu_mode = 'host-passthrough'
    lv.nested = true
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs'
  end

  config.vm.provider 'virtualbox' do |vb|
    vb.linked_clone = true
    vb.memory = 2*1024
    vb.cpus = 4
  end

  (1..number_of_nodes).each do |n|
    name = "k8s-#{n}"
    fqdn = "#{name}.example.test"
    ip = node_ip_addr.to_s; node_ip_addr = node_ip_addr.succ

    config.vm.define name do |config|
      config.vm.hostname = fqdn
      config.vm.network :private_network, ip: ip, libvirt__forward_mode: 'none', libvirt__dhcp_enabled: false
      config.vm.provision 'shell', path: 'provision-base.sh'
      config.vm.provision 'shell', path: 'provision-docker.sh'
      config.vm.provision 'shell', path: 'provision-kubernetes-tools.sh'
      config.vm.provision 'shell', path: 'provision-kubernetes-master.sh', args: [ip, pod_network_cidr] if ip == first_node_ip
      config.vm.provision 'shell', path: 'provision-kubernetes-worker.sh' if ip != first_node_ip
    end
  end
end
