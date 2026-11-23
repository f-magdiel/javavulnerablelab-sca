resource "aws_security_group" "bastion" {
  name        = "jvl-bastion"
  description = "Bastion con SSH abierto a Internet (prueba del gate)"

  ingress {
    description = "SSH desde cualquier lugar"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
