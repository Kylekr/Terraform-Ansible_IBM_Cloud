variable "ibm_bmx_api_key" {
  type = "string"
  default = "INPUT_YOUR_Bluemix_API_Key"
}

variable "ibm_sl_username" {
  type = "string"
  default = "IBM0000000"
}

variable "ibm_sl_api_key" {
  type = "string"
  default = "INPUT_YOUR_IaaS_API_Key"
}

variable "ssh_public_key" {
  type = "string"
  default = "INPUT_Your_PUB_SSH_Key"
}

variable "ibm_dc" {
  type = "string"
  default = "seo01"
}

variable "ibm_pod" {
  type = "string"
  default = "pod01"
}

variable "vm_count" {
  type = "string"
  default = "2"
}
