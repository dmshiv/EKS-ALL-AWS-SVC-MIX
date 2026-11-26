variable "app_parameters" {
  description = "Shared NON-SECRET String parameters (relative name => value), e.g. feature flags. Never put secrets here: use Secrets Manager (17) or a SecureString created out-of-band."
  type        = map(string)
  default = {
    "app/log_level"         = "INFO"
    "app/cache_ttl_seconds" = "60"
  }
}
