terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.72.0"
    }
  }
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.zone
}

# Сеть и подсеть
resource "yandex_vpc_network" "default" {
  name = "network-1"
}

resource "yandex_vpc_subnet" "default" {
  name           = "subnet-1"
  zone           = var.zone
  network_id     = yandex_vpc_network.default.id
  v4_cidr_blocks = ["10.0.1.0/24"]
}

# Группа безопасности — разрешаем HTTP (80) и SSH (22)
resource "yandex_vpc_security_group" "web_sg" {
  name        = "web-security-group"
  description = "Allow HTTP and SSH"
  network_id  = yandex_vpc_network.default.id

  ingress {
    protocol       = "TCP"
    description    = "HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]   # В продакшене лучше ограничить
    port           = 22
  }

  egress {
    protocol       = "ANY"
    description    = "Allow all outgoing"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Данные для cloud-init (установка Nginx)
locals {
  user_data = templatefile("${path.module}/user_data.yaml", {})
}

# Создание двух идентичных ВМ с помощью count
resource "yandex_compute_instance" "web" {
  count = 2

  name        = "web-${count.index + 1}"
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = "fd827b91d99psvq5fjit"  # Ubuntu 22.04 LTS
      size     = 20
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.default.id
    security_group_ids = [yandex_vpc_security_group.web_sg.id]
    nat                = true
  }

  metadata = {
    user-data = local.user_data
  }

  # Можно использовать depends_on, если требуется строгий порядок
}

# Целевая группа для балансировщика
resource "yandex_lb_target_group" "web_tg" {
  name = "web-target-group"

  # Добавляем созданные ВМ как цели
  dynamic "target" {
    for_each = yandex_compute_instance.web
    content {
      subnet_id = yandex_vpc_subnet.default.id
      address   = target.value.network_interface.0.ip_address
    }
  }
}

# Сетевой балансировщик нагрузки
resource "yandex_lb_network_load_balancer" "web_lb" {
  name = "web-load-balancer"

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.web_tg.id

    healthcheck {
      name = "http-healthcheck"
      interval = 2            # секунды
      timeout  = 1            # секунды
      healthy_threshold   = 3
      unhealthy_threshold = 2

      http_options {
        port = 80
        path = "/"
      }
    }
  }
}
