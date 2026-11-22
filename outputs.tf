output "loadbalancerdns" {
  value = aws_lb.myalb.dns_name
}

output "website_url" {
  value = "http://${aws_lb.myalb.dns_name}"
}
