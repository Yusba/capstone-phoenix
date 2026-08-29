data "aws_ami" "ubuntu" {
  # Pinned intentionally: do NOT use most_recent = true here.
  # If AWS publishes a newer Ubuntu 22.04 build, most_recent would
  # resolve to a different AMI ID on your NEXT terraform apply — even
  # if you only changed ssh_cidr — and Terraform treats a changed ami
  # as "replace this instance," destroying and recreating all 3 nodes
  # and wiping the entire cluster. This happened once already.
  # Pinned to the exact AMI ID currently running on the cluster.
  # To intentionally upgrade the base image later, look up a new AMI
  # ID deliberately and update this filter, right before a planned
  # full rebuild — never let it float automatically.
  owners = ["099720109477"] # Canonical

  filter {
    name   = "image-id"
    values = ["ami-099541a07a9bdb365"]
  }
}

resource "aws_key_pair" "cluster" {
  key_name   = "${var.project_name}-key"
  public_key = file(var.public_key_path)
}

resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.cluster.key_name

  # gp3 instead of the default gp2: gp2's baseline IOPS scale with disk
  # size (~24 IOPS for an 8GB volume) — once swap gets used under
  # memory pressure, that tiny IOPS budget becomes THE bottleneck,
  # causing 90%+ iowait and effectively freezing the API server even
  # though "load average" looks CPU-bound. gp3 has a flat 3000 IOPS
  # baseline regardless of size, and is also cheaper per-GB than gp2.
  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  # t3 instances are burstable: a "standard" credit mode throttles CPU
  # hard once your credit balance is depleted (common after sustained
  # troubleshooting load), which shows up as CPU steal time and makes
  # everything — including SSH itself — grind to a halt. "unlimited"
  # removes that ceiling. It's effectively free for short bursts;
  # only sustained high CPU for a long time incurs extra cost.
  credit_specification {
    cpu_credits = "unlimited"
  }

  # Extra safety net after an AMI-drift incident wiped this instance
  # once already. Terraform will now refuse to destroy this instance
  # even if a future plan calls for replacement — you'd have to
  # deliberately remove this block first, which is a good forcing
  # function to stop and ask "wait, why is this being replaced?"
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.project_name}-control-plane"
    Role = "control-plane"
  }
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.cluster.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
  }

  credit_specification {
    cpu_credits = "unlimited"
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.project_name}-worker-${count.index}"
    Role = "worker"
  }
}
