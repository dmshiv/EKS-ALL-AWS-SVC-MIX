output "vpce_security_group_id" {
  description = "SG attached to interface endpoints."
  value       = aws_security_group.vpce.id
}

output "gateway_endpoint_ids" {
  description = "S3 and DynamoDB gateway endpoint ids."
  value = {
    s3       = aws_vpc_endpoint.s3.id
    dynamodb = aws_vpc_endpoint.dynamodb.id
  }
}

output "interface_endpoint_ids" {
  description = "Interface endpoint ids keyed by service."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}
