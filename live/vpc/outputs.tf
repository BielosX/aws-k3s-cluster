output "vpc-id" {
  value = module.vpc.vpc-id
}

output "public-subnet-ids" {
  value = module.vpc.public-subnet-ids
}

output "private-subnet-ids" {
  value = module.vpc.private-subnet-ids
}