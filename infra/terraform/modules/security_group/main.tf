resource "aws_security_group" "cluster" {
  name        = "${var.project_name}-sg"
  description = "Least-privilege SG for the k3s cluster nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# --- SSH: your IP only, never 0.0.0.0/0 ---
resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.ssh_cidr]
  security_group_id = aws_security_group.cluster.id
  description       = "SSH from admin IP only"
}

# --- HTTP/HTTPS: public, for the Ingress controller ---
resource "aws_security_group_rule" "http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
  description       = "HTTP for ACME challenge + app"
}

resource "aws_security_group_rule" "https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
  description       = "HTTPS for the app"
}

# --- Kubernetes API (6443): admin IP only, NEVER 0.0.0.0/0 ---
# You need this open to your own IP (not just internal) because the
# guide has you fetch the kubeconfig and point it at the control
# plane's PUBLIC IP so `kubectl` works from your laptop.
resource "aws_security_group_rule" "k8s_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [var.ssh_cidr]
  security_group_id = aws_security_group.cluster.id
  description       = "Kubernetes API from admin IP only"
}


resource "aws_security_group_rule" "k8s_api_internal" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.cluster.id
  description       = "Kubernetes API, internal node-to-node only"
}


# --- Flannel VXLAN (UDP 8472): internal node-to-node only ---
# The guide lists this as a "Phase 3 fix" after the cluster is already
# broken. Adding it here up front means you never hit that failure.
resource "aws_security_group_rule" "flannel_vxlan" {
  type              = "ingress"
  from_port         = 8472
  to_port           = 8472
  protocol          = "udp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.cluster.id
  description       = "Flannel VXLAN, internal only"
}

# --- Kubelet metrics (TCP 10250): internal node-to-node only ---
resource "aws_security_group_rule" "kubelet_metrics" {
  type              = "ingress"
  from_port         = 10250
  to_port           = 10250
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.cluster.id
  description       = "Kubelet metrics, internal only"
}

# --- Egress: allow all outbound (pulling images, apt, Let's Encrypt, etc.) ---
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
  description       = "Allow all outbound"
}
