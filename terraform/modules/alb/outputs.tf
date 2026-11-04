output "dns_name" {
  value = aws_lb.this.dns_name
}

output "arn" {
  value = aws_lb.this.arn
}

output "target_group_arns" {
  value = {
    frontend = aws_lb_target_group.frontend.arn
    backend  = aws_lb_target_group.backend.arn
  }
}
