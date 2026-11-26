variable "visibility_timeout_seconds" {
  description = "How long a received message is hidden from other consumers. MUST exceed the worker's max processing time or messages are processed twice."
  type        = number
  default     = 60
}

variable "max_receive_count" {
  description = "Delivery attempts before a message is moved to the dead-letter queue."
  type        = number
  default     = 5
}
