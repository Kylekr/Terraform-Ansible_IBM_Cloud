# Create an SSH key. You can find the SSH key surfaces in the SoftLayer console under Devices > Manage > SSH Keys
# 기존에 등록한 SSH key 참조
data "ibm_compute_ssh_key" "key_1" {
  label = "key_1"
}

# 이미지 템플릿 참조
data "ibm_compute_image_template" "img_workshop_1" {
  name = "PetClinic_Kyle"
}

# 개인 Domain 참조
data "ibm_dns_domain" "workshop_domain" {
  name = "kylekr.com"
}

# Placement 그룹 생성
resource "ibm_compute_placement_group" "placement_group"  {
   name = "ws111_placement_group"
   datacenter = "${var.ibm_dc}"
   pod = "${var.ibm_pod}"
}

# ICOS 계정 생성
resource "ibm_object_storage_account" "kyle-workshop" {
}

# Security Group 기존에 디폴트로 있는 것 사용 
data "ibm_security_group" "allow_ssh" {
    name = "allow_ssh"
}

data "ibm_security_group" "allow_http" {
    name = "allow_http"
}

# Outbound를 열어주지 않으면 해당 VM 외부 통신 불가 
data "ibm_security_group" "allow_outbound" {
    name = "allow_outbound"
}

# 새로운 Security Group 생성 
resource "ibm_security_group" "allow_port_8080" {
    name = "kyle-sg-port8080"
    description = "allow my app traffic for port 8080"
}

resource "ibm_security_group" "allow_all_icmp" {
    name = "kyle-sg-icmp"
    description = "allow my app traffic for all icmp"
}

# 새롭게 생성한 Security Group에 Rule 생성
resource "ibm_security_group_rule" "allow_port_8080" {
    direction = "ingress"
    ether_type = "IPv4"
    port_range_min = 8080
    port_range_max = 8080
    protocol = "tcp"
    security_group_id = "${ibm_security_group.allow_port_8080.id}"
}

#  새롭게 생성한 allow_all_icmp에 3계층 icmp 추가
resource "ibm_security_group_rule" "allow_icmp" {
    direction = "ingress"
    protocol = "icmp"
    security_group_id = "${ibm_security_group.allow_all_icmp.id}"
}

# SSH key와 함께 VM 생성
resource "ibm_compute_vm_instance" "workshop_vm" {
  hostname          = "${format("vm%02d", count.index + 1)}"
  domain            = "${data.ibm_dns_domain.workshop_domain.name}"
  ssh_key_ids       = ["${data.ibm_compute_ssh_key.key_1.id}"]
  image_id          = "${data.ibm_compute_image_template.img_workshop_1.id}"
  placement_group_id = "${ibm_compute_placement_group.placement_group.id}"
  datacenter        = "${var.ibm_dc}"
  public_security_group_ids = ["${data.ibm_security_group.allow_ssh.id}"]
  public_security_group_ids = ["${data.ibm_security_group.allow_http.id}"]
  public_security_group_ids = ["${ibm_security_group.allow_port_8080.id}"]
  public_security_group_ids = ["${ibm_security_group.allow_all_icmp.id}"]
  public_security_group_ids = ["${data.ibm_security_group.allow_outbound.id}"]
  network_speed     = 100
  transient         = true
  flavor_key_name   = "C1_1X1X25"
  local_disk        = false
  tags = [
    "vm-workshop",
    "transient"
  ]
  wait_time_minutes = 10
  count = "${var.vm_count}"

# Ansible 적용 
  connection {
    user        = "root"
    type        = "ssh"
    private_key = "${file("~/.ssh/id_rsa")}"
    timeout     = "3m"
  }

  provisioner "remote-exec" {
    inline = [
      "hostname"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum -y update"
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y python"
    ]
  }

  provisioner "local-exec" {
    command = <<EOF
      echo "[demo]" > inventory
      echo "${ibm_compute_vm_instance.workshop_vm.0.ipv4_address} ansible_ssh_user=root ansible_ssh_private_key_file=~/.ssh/id_rsa" >> inventory
      EOF
  }

  provisioner "local-exec" {
    command = <<EOF
      ANSIBLE_HOST_KEY_CHECKING=False \
      ansible-playbook -i inventory playbook-pet.yaml
      EOF
  }
}

# LBaaS 생성
# HTTPS 할 경우에는 SSL Certificate 필요
resource "ibm_lbaas" "lbaas" {
  name        = "terraformLB"
  subnets = ["${ibm_compute_vm_instance.workshop_vm.0.private_subnet_id}"]

  protocols = [{
    frontend_protocol     = "HTTP"
    frontend_port         = 80
    backend_protocol      = "HTTP"
    backend_port          = 80
    load_balancing_method = "round_robin"
  },
    {
      frontend_protocol     = "HTTP"
      frontend_port         = 8080
      backend_protocol      = "HTTP"
      backend_port          = 8080
      load_balancing_method = "round_robin"
    },
    {
      frontend_protocol     = "TCP"
      frontend_port         = 99
      backend_protocol      = "TCP"
      backend_port          = 99
      load_balancing_method = "round_robin"
    },
    ]
}

# LBaaS 에 멤버 등록 
resource "ibm_lbaas_server_instance_attachment" "lbaas_member" {
  count = "${var.vm_count}"
  private_ip_address = "${element(ibm_compute_vm_instance.workshop_vm.*.ipv4_address_private,count.index)}"
  weight             = 40
  lbaas_id           = "${ibm_lbaas.lbaas.id}"
}

# LBaaS 헬스 모니터링
resource "ibm_lbaas_health_monitor" "lbaas_hm" {
  protocol = "${ibm_lbaas.lbaas.health_monitors.0.protocol}"
  port = "${ibm_lbaas.lbaas.health_monitors.0.port}"
  timeout = 3
  interval = 5
  max_retries = 6
  url_path = "/"
  lbaas_id = "${ibm_lbaas.lbaas.id}"
  monitor_id = "${ibm_lbaas.lbaas.health_monitors.0.monitor_id}"
  // LBaaS 멤버 등록과 모니터링은 병렬 실행이 안되기 때문에(둘다 LB에 영향을 주기 때문에)  dependson 을 해줘야한다. 
  depends_on = ["ibm_lbaas_server_instance_attachment.lbaas_member"]
}

# DNS A Record 
resource "ibm_dns_record" "workshop" {
  data = "${element(ibm_compute_vm_instance.workshop_vm.*.ipv4_address, count.index)}"
  domain_id = "${data.ibm_dns_domain.workshop_domain.id}"
  host = "${element(ibm_compute_vm_instance.workshop_vm.*.hostname, count.index)}"
  ttl = 900
  type = "a"
  count = "${var.vm_count}"
}

# DNS CNAME 등록 
resource "ibm_dns_record" "cname" {
    data = "${ibm_lbaas.lbaas.vip}"
    domain_id = "${data.ibm_dns_domain.workshop_domain.id}"
    host = "workshop"
    ttl = 900
    type = "cname"
}
