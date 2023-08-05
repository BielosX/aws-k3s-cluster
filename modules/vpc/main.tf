resource "aws_vpc" "vpc" {
  enable_dns_hostnames = true
  enable_dns_support = true
  cidr_block = var.cidr-block
}

locals {
  prefix-extension = ceil(log(length(var.availability-zones) * 2, 2))
}

resource "aws_subnet" "public-subnet" {
  count = length(var.availability-zones)
  vpc_id = aws_vpc.vpc.id
  availability_zone = var.availability-zones[count.index]
  map_public_ip_on_launch = true
  cidr_block = cidrsubnet(aws_vpc.vpc.cidr_block,
    local.prefix-extension,
    count.index + 1)
  tags = {
    Name: "public-subnet"
  }
}

resource "aws_subnet" "private-subnet" {
  count = length(var.availability-zones)
  vpc_id = aws_vpc.vpc.id
  availability_zone = var.availability-zones[count.index]
  map_public_ip_on_launch = false
  cidr_block = cidrsubnet(aws_vpc.vpc.cidr_block,
    local.prefix-extension,
    length(var.availability-zones) + count.index + 1)
  tags = {
    Name: "private-subnet"
  }
}

resource "aws_internet_gateway" "internet-gateway" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_eip" "eip" {
  depends_on = [aws_internet_gateway.internet-gateway]
  count = var.single-nat-gateway ? 1 : length(var.availability-zones)
  domain = "vpc"
}

resource "aws_nat_gateway" "nat-gateway" {
  count = var.single-nat-gateway ? 1 : length(var.availability-zones)
  subnet_id = aws_subnet.public-subnet[count.index].id
  allocation_id = aws_eip.eip[count.index].id
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gateway.id
  }
  tags = {
    Name: "public-route-table"
  }
}

resource "aws_route_table" "private-route-table" {
  vpc_id = aws_vpc.vpc.id
  dynamic "route" {
    for_each = aws_nat_gateway.nat-gateway[*].id
    content {
      cidr_block = "0.0.0.0/0"
      nat_gateway_id = route.value
    }
  }
  tags = {
    Name: "private-route-table"
  }
}

resource "aws_route_table_association" "public-association" {
  count = length(var.availability-zones)
  subnet_id = aws_subnet.public-subnet[count.index].id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "private-association" {
  count = length(var.availability-zones)
  subnet_id = aws_subnet.private-subnet[count.index].id
  route_table_id = aws_route_table.private-route-table.id
}