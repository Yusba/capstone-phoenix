module "network" {
  source = "./modules/network"

  project_name        = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
}

module "security_group" {
  source = "./modules/security_group"

  project_name = var.project_name
  vpc_id       = module.network.vpc_id
  vpc_cidr     = module.network.vpc_cidr
  ssh_cidr     = var.ssh_cidr
}

module "compute" {
  source = "./modules/compute"

  project_name       = var.project_name
  instance_type      = var.instance_type
  worker_count       = var.worker_count
  subnet_id          = module.network.subnet_id
  security_group_id  = module.security_group.security_group_id
  public_key_path    = var.public_key_path
}
