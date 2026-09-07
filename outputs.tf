output "load_balancer_external_ip" {
  value = one(one(yandex_lb_network_load_balancer.web_lb.listener).external_address_spec).address
  description = "Внешний IP-адрес балансировщика"
}

output "vm_internal_ips" {
  value = yandex_compute_instance.web[*].network_interface.0.ip_address
  description = "Внутренние IP-адреса ВМ"
}
