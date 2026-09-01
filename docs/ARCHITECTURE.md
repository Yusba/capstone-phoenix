# Architecture

## 1. Topology diagram 

Internet ──DNS(nip.io)──▶ taskapp.54.74.194.170.nip.io
│
▼
ingress controller (node: worker, ip-172-31-1-112) ──TLS terminated by cert-manager──┐
│ │
▼ ▼
frontend Service ──▶ frontend Pods (nodes: worker-0, worker-1) backend Service ──▶ backend Pods (nodes: worker-0, worker-1)
│ /api proxy │
└────────────────────────────────────────────────────▶│
▼
postgres Service ──▶ postgres-0 (PVC on worker node)


Control-plane node (ip-172-31-1-23) is tainted `node-role.kubernetes.io/control-plane:NoSchedule`
and runs no application workloads — only k3s server, cert-manager, and Argo CD's
platform components.

## 2. Node & network

- Nodes: 1 control-plane + 2 workers, all `t3.micro`, `eu-west-1` region, single AZ
- Network: single public subnet, all 3 nodes have direct public IPs (no NAT gateway,
  to avoid unnecessary cost)
- Firewall: ports 80/443 open to the world (ingress traffic); port 22 restricted to
  the operator's current IP only; port 6443 (Kubernetes API) restricted to the
  operator's IP — never exposed to 0.0.0.0/0; internal-only rules for Flannel VXLAN
  (UDP 8472) and kubelet metrics (TCP 10250) between nodes for cross-node pod
  networking

## 3. Request flow

A request to `taskapp.54.74.194.170.nip.io` resolves via nip.io directly to the
control-plane's public IP, hits the ingress-nginx controller (listening on a worker
node via its NodePort/LoadBalancer service) on ports 80/443, where cert-manager's
issued Let's Encrypt certificate terminates TLS. The ingress routes to the `frontend`
Service, which serves the React build via nginx; nginx reverse-proxies any `/api/*`
path to the `backend` Service (Flask/gunicorn), which in turn connects to the
`postgres` Service backed by a StatefulSet with a persistent volume.

## 4. The single-server assumptions you fixed

| Single-server assumption | Why it breaks at scale | How you fixed it |
|---|---|---|
| migrate-on-boot in the entrypoint | 2+ replicas race on `alembic upgrade head` | Separate migration Job (`cd /app && alembic upgrade head`) runs once before backend replicas start |
| named volume on the host | Pods reschedule across nodes; a host-local volume isn't visible from another node | Postgres StatefulSet with a PVC backed by the cluster's storage class (local-path-provisioner) |
| `ports:` published on the host | Many Pods, many nodes, one front door needed | ingress-nginx Ingress resource routes all external traffic through one controller |
| manual restart on failure | No human watching a multi-replica, multi-node cluster | liveness/readiness/startup probes on every workload; Kubernetes restarts/reroutes automatically |
| single instance, brief downtime on redeploy | Multi-replica services must stay available during rollout | RollingUpdate strategy with `maxUnavailable: 0` across 2+ replicas |
| .env file / Portainer env vars on one host | Secrets need to be available to any node a Pod schedules on | Kubernetes Secret + ConfigMap, split the same way (secret vs non-secret config) |

## 5. Choices & trade-offs

- **Raw YAML vs Helm vs kustomize**: raw YAML manifests, applied via Argo CD. Chosen
  for simplicity and transparency at this project's scale — every resource is
  explicit and easy to review in a GitOps diff, without an extra templating layer.
- **ingress-nginx vs k3s Traefik**: k3s's built-in Traefik was disabled
  (`--disable traefik` at install) in favor of ingress-nginx, which has broader
  documentation and is the more common production choice, making cert-manager's
  HTTP-01 challenge integration more standard.
- **CNI / NetworkPolicy enforcement**: k3s ships with Flannel by default, which does
  not enforce NetworkPolicy. [Fill in based on whether you implemented this Advanced
  requirement.]
- **Secrets approach**: out-of-band (`kubectl create secret` / plain Kubernetes
  Secret), not Sealed/External Secrets. Chosen given the project's timeframe and
  free-tier constraints — documented here as a known trade-off rather than hidden;
  a production system would use Sealed Secrets or an external secrets manager so
  the Secret manifest itself could live safely in git.
ENDOFFILE
