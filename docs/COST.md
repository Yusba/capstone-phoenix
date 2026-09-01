# Cost

## Monthly itemized cost

| Item | Spec | Qty | $/mo |
|---|---|---:|---:|
| control-plane VM | t3.micro (free-tier eligible) | 1 | $0 (free tier) |
| worker VMs | t3.micro (free-tier eligible) | 2 | $0 (free tier) |
| root EBS volume (control-plane) | gp3, 20GB | 1 | ~$1.60 |
| root EBS volume (workers) | gp3, 8GB each | 2 | ~$1.28 |
| load balancer / elastic IP | none used (direct public IPs on instances) | 0 | $0 |
| block storage (PVC) | local-path-provisioner, uses node's root EBS | - | included above |
| object storage (Terraform state) | S3 bucket + DynamoDB lock table | 1 each | ~$0.01 |
| DNS / domain | nip.io (free, no registration) | - | $0 |
| **Total** | | | **~$3/mo** |

All 3 EC2 instances are `t3.micro`, within AWS's standard free-tier allowance
(750 hrs/month combined for t2/t3.micro), so compute itself is $0. The only real
recurring cost is EBS storage beyond the free tier's 30GB combined allowance
(currently well within it) — the ~$3/mo above is a conservative estimate and in
practice this project ran within free tier for compute the whole time.

## Compared to the single-server Compose+Portainer deploy

- That stack cost roughly: $0/mo (single free-tier-eligible EC2 instance, no
  extra EBS resizing needed for a lighter single-container stack)
- This cluster costs: ~$3/mo (see breakdown above — mostly just the resized
  control-plane EBS volume)
- **What the extra spend buys**: high availability (2+ replicas per tier spread
  across nodes, surviving a node failure), zero-downtime rolling deploys, GitOps-driven
  reconciliation instead of manual redeploys, and a real path to autoscaling (HPA).
  For a real production workload with actual users, this is a clearly worthwhile
  trade — a few dollars a month for the ability to survive a node dying without
  downtime is cheap insurance.
- **When it's NOT worth it**: for a genuinely low-traffic personal project or an
  early prototype with no uptime guarantees, the single-server Portainer setup is
  simpler to operate and has effectively the same or lower cost. The complexity
  of a multi-node cluster (and its own overhead, discussed below) only pays off
  once availability and scale actually matter.

## How I'd halve this

The clearest win, discovered the hard way during this project: `t3.micro`'s CPU
credit balance is not enough to run k3s plus cert-manager, Argo CD, and
ingress-nginx continuously — sustained load exhausts credits and the API server
becomes unresponsive for minutes at a time (confirmed via CloudWatch
`CPUCreditBalance` sitting at 0.0 for hours). Rather than pay for a larger
instance type, the actual fix that costs nothing is to **not run every
component continuously**: scale non-critical platform pieces (cert-manager,
Argo CD's repo-server/applicationset-controller) to 0 replicas when not
actively syncing or issuing a certificate, and scale them up only in short,
deliberate bursts. This halves *effective* load without halving node count,
and is arguably a better fit for a project at this traffic level than paying
for a bigger box just to keep idle tooling always-on.
