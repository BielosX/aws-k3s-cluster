output "public-subnet-ids" {
  value = aws_subnet.public-subnet[*].id
}

output "private-subnet-ids" {
  value = aws_subnet.private-subnet[*].id
}

output "vpc-id" {
  value = aws_vpc.vpc.id
}