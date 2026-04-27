output "public_ip" {
  description = "Public IP of the app server"
  value       = aws_instance.app_server.public_ip
}

output "ssh_command" {
  description = "Command to SSH into the instance"
  value       = "ssh -i ~/.ssh/devops-tutorial.pem ubuntu@${aws_instance.app_server.public_ip}"
}