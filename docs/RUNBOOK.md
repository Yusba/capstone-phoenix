# Runbook

## Provision from zero

```bash
# 0. Check your current public IP and update ssh_cidr in infra/terraform/terraform.tfvars
curl ifconfig.me

# 1. infra
cd infra/terraform
terraform init
terraform apply

# 2. cluster
cd ../ansible
ansible-playbook -i inventory/hosts.ini install-k3s.yml

# 3. kubeconfig — fetch from control-plane and point at its public IP
ssh -i ~/.ssh/id_rsa ubuntu@<control-plane-public-ip> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
sed -i 's/127.0.0.1/<control-plane-public-ip>/' ~/.kube/config
chmod 600 ~/.kube/config
kubectl get nodes   # expect all 3 nodes Ready

# 4. platform
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/core-install.yaml
# core-install does not create the default AppProject automatically — create it manually:
kubectl apply -f gitops/default-appproject.yaml

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml

# 5. GitOps takes over
kubectl apply -f gitops/taskapp-application.yaml
kubectl get application taskapp -n argocd   # expect Synced / Healthy within ~30s
```

## Day-2 operations

- **Scale a tier:** edit the `replicas:` field in the relevant manifest under
  `manifests/`, commit, and push. Argo CD's automated sync (`prune: true,
  selfHeal: true`) applies it within its polling interval — do not `kubectl scale`
  directly in normal operation, since Argo CD's self-heal will revert a manual
  change back to whatever git says.
- **Roll back a bad deploy:** `git revert <bad-commit>` and push — Argo CD syncs
  the reverted state automatically. This is safer than `kubectl rollout undo`,
  which would leave git and the cluster out of sync.
- **Run a new migration safely:** update the migration Job's manifest (new image
  tag containing the migration), commit, push. The Job runs once before the
  backend Deployment's new replicas start — never run migrations by editing the
  running Deployment's entrypoint directly.
- **Rotate a secret:** update the Secret's value (`kubectl create secret ... --dry-run=client -o yaml` to regenerate, or edit directly), reapply, then
  `kubectl rollout restart deployment/backend -n taskapp` so running Pods pick up
  the new value (Kubernetes does not automatically restart Pods on Secret changes).

## Failure recovery (you'll demo one of these live)

- **A worker node dies / is drained:** Pods on that node are marked `NotReady`
  after the node-monitor grace period (~40s default), then rescheduled onto the
  remaining worker(s) — `topologySpreadConstraints` on backend/frontend
  Deployments means the replacement lands on a different node than its sibling.
  Recovery is typically under 1-2 minutes for pod rescheduling.
```bash
  kubectl drain <node> --ignore-daemonsets --delete-emptydir-data   # the live-demo command
  kubectl get pods -n taskapp -o wide -w   # watch pods reschedule onto remaining nodes
  kubectl uncordon <node>   # bring it back afterward
```

- **A backend Pod crashloops:** check logs from the current and previous container
  instance, then describe for events (OOMKilled, failed probes, image pull errors):
```bash
  kubectl logs <pod> -n taskapp --previous
  kubectl describe pod <pod> -n taskapp   # check Events section at the bottom
```
  Common causes hit during this project: migration race conditions (fixed by
  running migrations as a separate Job, not in the entrypoint), and wrong
  environment variable names in the Secret/ConfigMap.

- **A bad migration:** since migrations run as a one-off Job rather than in the
  app's entrypoint, a bad migration is isolated — the currently-running backend
  replicas keep serving on the old schema. Recovery: `kubectl exec` into
  `postgres-0` to inspect/manually fix the `alembic_version` table if the
  migration failed partway, or write a compensating migration and let the Job
  rerun on redeploy. Never run destructive `ALTER TABLE` fixes by hand in
  production — treat any manual DB intervention here as a stopgap, then commit
  the real fix as a proper migration.

- **Postgres Pod is rescheduled:** because Postgres runs as a StatefulSet with a
  PersistentVolumeClaim (not a bare Deployment), Kubernetes guarantees the same
  PVC re-attaches to the replacement Pod regardless of which node it lands on.
  To prove this: `kubectl delete pod postgres-0 -n taskapp`, wait for the
  replacement to become `Running` and `1/1` Ready, then query data that existed
  before the delete — it persists because the PVC (not the Pod) owns the data.

## Known operational quirks (specific to this
 cluster)

- **Public IP drift:** the operator's IP changes frequently between sessions.
  Always run `curl ifconfig.me`, compare against `ssh_cidr` in
  `infra/terraform/terraform.tfvars`, update and `terraform apply` if it's
  changed — otherwise SSH/kubectl access is blocked by the security group.
- **Control-plane needs a restart most sessions:** `t3.micro`'s CPU credits
  deplete under sustained load; if `kubectl` times out or refuses connections,
  first check `aws ec2 describe-instance-status` (an AWS-level "impaired"
  status needs `aws ec2 reboot-instances`, not just a service restart), then
  `sudo systemctl restart k3s` on the control-plane if the instance itself is
  healthy but k3s is unresponsive.
- **Disk-pressure taints can block ALL scheduling:** worker nodes can hit
  kubelet's disk-pressure threshold from accumulated container images/logs,
  tainting themselves `node.kubernetes.io/disk-pressure:NoSchedule` — this
  blocks scheduling cluster-wide, not just on that node. Fix: `sudo k3s crictl
  rmi --prune` and `sudo journalctl --vacuum-time=2d` on the affected node; the
  taint clears automatically once usage drops.
