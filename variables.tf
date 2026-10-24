variable "project_name" {
  type        = string
  default     = "spot-lab"
  description = "Project name prefix for resources"
}

variable "custom_header_secret" {
  type        = string
  default     = "MySuperSecretValue123!" # Ideally injected via TF_VAR_custom_header_secret
  description = "Secret value for X-Custom-Secret header to verify CloudFront to ALB traffic"
}
