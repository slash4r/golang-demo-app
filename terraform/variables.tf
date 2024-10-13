variable "public_subnet_cidrs" {
 type        = list(string)
 description = "Public Subnet CIDR values"
 default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

# region eu-north-1
variable "azs" {
    type        = list(string)
    description = "Availability Zones"
    default     = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
}