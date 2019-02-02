# Output 설정
output "Server IPs" {
  value = "${formatlist("%s = %s", "${formatlist("%s.%s", ibm_compute_vm_instance.workshop_vm.*.hostname, ibm_compute_vm_instance.workshop_vm.*.domain)}", 
ibm_compute_vm_instance.workshop_vm.*.ipv4_address)}"
}

output "Access URL" {
  value = "${format("http://%s.%s/", ibm_dns_record.cname.host, data.ibm_dns_domain.workshop_domain.name)}"
}


