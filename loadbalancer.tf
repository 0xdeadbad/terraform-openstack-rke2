locals {
  server_nodes = flatten([for s in module.servers : [for ip in s.internal_ips : { "ip" = ip, "name" : s.names[index(s.internal_ips, ip)] }]])
  k8s_cidr     = sort(concat([var.subnet_servers_cidr, var.subnet_agents_cidr], var.rules_k8s_cidr != "" && var.rules_k8s_cidr != null ? [var.rules_k8s_cidr] : []))
  ssh_cidr     = var.rules_ssh_cidr != "" && var.rules_ssh_cidr != null ? [var.rules_ssh_cidr] : []
  rke2_cidr    = [var.subnet_servers_cidr, var.subnet_agents_cidr]
}

resource "openstack_lb_loadbalancer_v2" "lb" {
  name                  = "${var.name}-lb"
  vip_network_id        = openstack_networking_network_v2.net.id
  vip_address           = local.internal_ip
  admin_state_up        = "true"
  loadbalancer_provider = "octavia"
  security_group_ids    = [openstack_networking_secgroup_v2.lb.id]
}

resource "openstack_networking_floatingip_v2" "external" {
  pool    = var.floating_pool
  port_id = openstack_lb_loadbalancer_v2.lb.vip_port_id
}

resource "openstack_lb_listener_v2" "ssh" {
  count           = length(local.ssh_cidr) > 0 ? 1 : 0
  name            = "server SSH"
  protocol        = "TCP"
  protocol_port   = 22
  loadbalancer_id = openstack_lb_loadbalancer_v2.lb.id
  allowed_cidrs   = local.ssh_cidr
}

resource "openstack_lb_pool_v2" "ssh" {
  count       = length(local.ssh_cidr) > 0 ? 1 : 0
  name        = "server SSH"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.ssh[0].id
}

resource "openstack_lb_monitor_v2" "ssh" {
  count       = length(local.ssh_cidr) > 0 ? 1 : 0
  name        = "SSH"
  pool_id     = openstack_lb_pool_v2.ssh[0].id
  type        = "TCP"
  delay       = 5
  timeout     = 5
  max_retries = 3
}

resource "openstack_lb_members_v2" "ssh" {
  count   = length(local.ssh_cidr) > 0 ? 1 : 0
  pool_id = openstack_lb_pool_v2.ssh[0].id

  dynamic "member" {
    for_each = local.server_nodes
    content {
      name          = member.value.name
      address       = member.value.ip
      protocol_port = 22
    }
  }
}


resource "openstack_lb_listener_v2" "k8s" {
  name            = "k8s"
  protocol        = "TCP"
  protocol_port   = 6443
  loadbalancer_id = openstack_lb_loadbalancer_v2.lb.id
  allowed_cidrs   = local.k8s_cidr
}

resource "openstack_lb_pool_v2" "k8s" {
  name        = "k8s"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.k8s.id
}

resource "openstack_lb_monitor_v2" "k8s" {
  name        = "k8s"
  pool_id     = openstack_lb_pool_v2.k8s.id
  type        = "TCP"
  delay       = 5
  timeout     = 5
  max_retries = 3
}

resource "openstack_lb_members_v2" "k8s" {
  pool_id = openstack_lb_pool_v2.k8s.id

  dynamic "member" {
    for_each = local.server_nodes
    content {
      name          = member.value.name
      address       = member.value.ip
      protocol_port = 6443
    }
  }
}


resource "openstack_lb_listener_v2" "rke2" {
  name            = "rke2"
  protocol        = "TCP"
  protocol_port   = 9345
  loadbalancer_id = openstack_lb_loadbalancer_v2.lb.id
  allowed_cidrs   = local.rke2_cidr
}

resource "openstack_lb_pool_v2" "rke2" {
  name        = "rke2"
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  listener_id = openstack_lb_listener_v2.rke2.id
}

resource "openstack_lb_monitor_v2" "rke2" {
  name        = "rke2"
  pool_id     = openstack_lb_pool_v2.rke2.id
  type        = "TCP"
  delay       = 5
  timeout     = 5
  max_retries = 3
}

resource "openstack_lb_members_v2" "rke2" {
  pool_id = openstack_lb_pool_v2.rke2.id

  dynamic "member" {
    for_each = local.server_nodes
    content {
      name          = member.value.name
      address       = member.value.ip
      protocol_port = 9345
    }
  }
}