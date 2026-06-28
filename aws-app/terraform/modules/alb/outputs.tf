output "alb_dns_name" {
  description = "ALBのDNS名"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALBのARN"
  value       = aws_lb.main.arn
}

output "target_group_blue_arn" {
  description = "Blue Target GroupのARN"
  value       = aws_lb_target_group.blue.arn
}

output "target_group_green_arn" {
  description = "Green Target GroupのARN"
  value       = aws_lb_target_group.green.arn
}

output "target_group_blue_name" {
  description = "Blue Target Groupの名前"
  value       = aws_lb_target_group.blue.name
}

output "target_group_green_name" {
  description = "Green Target Groupの名前"
  value       = aws_lb_target_group.green.name
}

output "listener_prod_arn" {
  description = "本番リスナー（:80）のARN"
  value       = aws_lb_listener.prod.arn
}

output "listener_test_arn" {
  description = "テストリスナー（:8080）のARN"
  value       = aws_lb_listener.test.arn
}
