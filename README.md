# homelab

A local Kubernetes lab that runs a Backstage internal developer portal, deployed with GitOps.

Everything in the cluster, including Argo CD itself, is defined in this repo and applied by Argo CD.
Secret values are kept in Vault, never in Git.

## Stack

| Layer | Tool | Notes |
|---|---|---|
| Container runtime | Docker runtime on macOS (e.g. OrbStack) | Provides the Linux VM |
| Cluster | k3d running k3s | 1 server, 2 agents, cluster name `homelab` |
| Ingress | Traefik (bundled with k3s) | Ports 80/443 mapped to localhost |
| Storage | local-path (bundled with k3s) | Used by Postgres and Vault |
| GitOps | Argo CD | Chart `argo-cd` 9.5.11, manages itself from `apps/argocd.yaml` |
| Image updates | Argo CD Image Updater | Chart 1.3.1, commits new image tags to this repo |
| Database | PostgreSQL 17 | Plain StatefulSet, 2Gi volume |
| Portal | Backstage | Wrapper chart in `charts/backstage` around the official chart 2.10.2 |
| Secrets manager | HashiCorp Vault | Chart 0.34.1, standalone, file storage, 1Gi volume, manual unseal |
| Secrets sync | External Secrets Operator | Chart 2.12.0, logs in to Vault with Kubernetes auth |

## URLs

- Backstage: http://backstage.localhost (GitHub sign-in only)
- Argo CD: http://argocd.localhost (user `admin`)
- Vault: http://vault.localhost
- Services created from the template: http://<name>.localhost

## How it fits together

1. **Git is the source of truth.** `bootstrap/root.yaml` is applied once by hand. It points Argo CD at `apps/`, and every file there is one Application.
2. **Argo CD manages itself.** `apps/argocd.yaml` holds Argo CD's own chart and settings, including the read-only `backstage` API account.
3. **Secrets never enter Git.** Values are stored in Vault. `ExternalSecret` resources in Git name the Vault paths, and External Secrets Operator creates the Kubernetes Secrets.
4. **Images are built by CI and deployed automatically.**
   - A push to an app repo builds an image and pushes it to GHCR with a `sha-<commit>` tag.
   - Argo CD Image Updater sees the new tag and commits it to this repo.
   - Argo CD then rolls it out.
5. **Private images work everywhere.** A GHCR pull secret from Vault is copied into every namespace labelled `homelab/ghcr-pull: "true"`.
6. **Backstage connects to everything else:**
   - GitHub, with a token for the catalog and scaffolder, and OAuth for sign-in.
   - The cluster, through its own read-only service account (Kubernetes tab).
   - Argo CD, through a read-only API account (sync and health per component).
7. **The golden path.** The `go-service` template creates a service repo, opens a pull request on this repo with the service's Argo CD Application, manifests and image updater, and registers it in the catalog. Merging the pull request deploys it.
8. **Traefik routes `*.localhost` hostnames** to Backstage, Argo CD, Vault and every templated service.

Related repos:
- `praveenbhatk8s/backstage`: the Backstage app source and its image build workflow.
- One repo per service created from the template, for example `praveenbhatk8s/hello`.

## Repository layout

```
bootstrap/root.yaml                      Root Application; the only manifest applied by hand
scripts/homelab-up.sh                    Starts OrbStack and the cluster, unseals Vault, re-syncs secrets

apps/argocd.yaml                         Argo CD itself (Helm chart), manual-prune, self-heal
apps/argocd-image-updater.yaml           Argo CD Image Updater (Helm chart)
apps/image-updater-config.yaml           Image Updater credentials and ImageUpdater resources
apps/vault.yaml                          HashiCorp Vault (Helm chart)
apps/external-secrets.yaml               External Secrets Operator (Helm chart)
apps/secret-store.yaml                   Vault connection and GHCR pull secret
apps/postgres.yaml                       Postgres
apps/backstage.yaml                      Backstage, from charts/backstage
apps/backstage-secrets.yaml              Backstage's ExternalSecrets
apps/backstage-rbac.yaml                 Backstage's read-only cluster access
apps/<service>.yaml                      One per templated service, added by its pull request

charts/backstage/Chart.yaml              Wrapper chart depending on the official Backstage chart
charts/backstage/Chart.lock              Locked dependency version
charts/backstage/charts/                 Vendored official chart (backstage-2.10.2.tgz)
charts/backstage/values.yaml             All Backstage settings and app config
charts/backstage/.argocd-source-backstage.yaml  Image tag written by Image Updater (appears after its first update)

manifests/secret-store/cluster-secret-store.yaml  ClusterSecretStore pointing at Vault
manifests/secret-store/ghcr-pull.yaml    ClusterExternalSecret: GHCR pull secret for labelled namespaces
manifests/postgres/                      StatefulSet, Service, ExternalSecret for postgres-credentials
manifests/backstage-secrets/             GitHub and Argo CD credentials for Backstage
manifests/backstage-rbac/rbac.yaml       Read-only ClusterRole and binding for the backstage service account
manifests/image-updater/credentials.yaml Git push and GHCR read credentials for Image Updater
manifests/image-updater/<app>.yaml       One ImageUpdater resource per app
manifests/<service>/                     Kustomization, Deployment, Service, Ingress per templated service

templates/go-service/template.yaml       The Backstage software template
templates/go-service/skeleton/           Files for the new service repo
templates/go-service/gitops/             Files for the pull request on this repo
templates/utility-delivery-labs/         A second template (not yet wired to Image Updater)
```

## Secrets in Vault

| Vault path | Keys | Becomes | Used by |
|---|---|---|---|
| `secret/backstage/postgres` | `POSTGRES_USER`, `POSTGRES_PASSWORD` | `backstage/postgres-credentials` | Postgres, Backstage |
| `secret/backstage/github` | `GITHUB_TOKEN`, `AUTH_GITHUB_CLIENT_ID`, `AUTH_GITHUB_CLIENT_SECRET` | `backstage/backstage-github` | Backstage integration and sign-in |
| `secret/backstage/argocd` | `ARGOCD_AUTH_TOKEN` | `backstage/backstage-argocd` | Backstage Argo CD plugin |
| `secret/ghcr/pull` | `GHCR_USERNAME`, `GHCR_TOKEN` | `ghcr-pull` in each labelled namespace; part of `argocd/image-updater-creds` | Pulling private images; Image Updater registry access |
| `secret/argocd/image-updater` | `GIT_USERNAME`, `GIT_TOKEN` | `argocd/image-updater-creds` | Image Updater pushing tag commits |

Tokens and their scopes:

| Token | Scope |
|---|---|
| Backstage GitHub token (classic) | `repo`, `workflow` |
| GHCR pull token (classic) | `read:packages` only |
| Image Updater token (fine-grained) | `homelab` repo only, Contents: read and write |

Kept outside the cluster, in a password manager: the Vault unseal key and root token. Backups of Vault are useless without them.

## Rebuilding from scratch

### 1. Tools

```bash
brew install orbstack k3d kubectl helm argocd
```

### 2. Cluster

```bash
k3d cluster create homelab \
  --servers 1 --agents 2 \
  -p "80:80@loadbalancer" \
  -p "443:443@loadbalancer"
```

### 3. Argo CD (first install only)

Install the same chart version as `apps/argocd.yaml`; Argo CD takes over its own management once `root` is applied.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --version 9.5.11 \
  -n argocd --create-namespace \
  --set global.domain=argocd.localhost \
  --set server.ingress.enabled=true \
  --set server.ingress.ingressClassName=traefik \
  --set 'configs.params.server\.insecure=true'

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### 4. Bootstrap GitOps

```bash
kubectl apply -f bootstrap/root.yaml
kubectl -n argocd get applications
```

Vault comes up sealed. Apps that need secrets wait until steps 5 and 6 are done.

### 5. Vault

To restore from a backup instead, skip this step and follow "Restoring Vault" below.

Initialise it once:

```bash
kubectl -n vault exec -it vault-0 -- vault operator init -key-shares=1 -key-threshold=1
```

Store the unseal key and root token in a password manager. Then:

```bash
kubectl -n vault exec -it vault-0 -- vault operator unseal      # paste the unseal key
kubectl -n vault exec -it vault-0 -- sh
```

Inside the pod:

```sh
vault login                                                    # paste the root token
vault secrets enable -path=secret kv-v2
vault auth enable kubernetes
vault write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc
vault policy write external-secrets - <<POLICY
path "secret/data/*" { capabilities = ["read"] }
POLICY
vault write auth/kubernetes/role/external-secrets bound_service_account_names=external-secrets bound_service_account_namespaces=external-secrets policies=external-secrets ttl=1h
```

### 6. Secrets

You need:
- The three GitHub tokens from the table above.
- A GitHub OAuth app with homepage `http://backstage.localhost` and callback `http://backstage.localhost/api/auth/github/handler/frame`.
- An Argo CD token for the `backstage` account: `argocd login argocd.localhost --plaintext --grpc-web --username admin`, then `argocd account generate-token --account backstage`.

Inside the Vault pod:

```sh
vault kv put secret/backstage/postgres POSTGRES_USER=backstage POSTGRES_PASSWORD='<password>'
vault kv put secret/backstage/github GITHUB_TOKEN='<token>' AUTH_GITHUB_CLIENT_ID='<id>' AUTH_GITHUB_CLIENT_SECRET='<secret>'
vault kv put secret/backstage/argocd ARGOCD_AUTH_TOKEN='<token>'
vault kv put secret/ghcr/pull GHCR_USERNAME=praveenbhatk8s GHCR_TOKEN='<token>'
vault kv put secret/argocd/image-updater GIT_USERNAME=praveenbhatk8s GIT_TOKEN='<token>'
```

Check that everything synced:

```bash
kubectl get clustersecretstore vault
kubectl get externalsecret -A
```

### 7. Backstage

The image comes from GHCR, so nothing needs building locally. If Backstage started before its secrets existed, restart it:

```bash
kubectl -n backstage rollout restart deploy/backstage
```

## Day-to-day

**Always `git pull` before editing this repo.** Image Updater commits here too, so a stale checkout will have its push rejected.

**Release a new build of Backstage or a service**
1. Push to `main` in the app's repo.
2. Wait for the build workflow to go green.

Image Updater commits the new tag here within a few minutes, and Argo CD rolls it out. Check progress with:

```bash
kubectl -n argocd logs deploy/argocd-image-updater --tail=40
```

**Change Backstage settings:** edit `charts/backstage/values.yaml`, not `apps/backstage.yaml`.

**Upgrade Argo CD:** change `targetRevision` in `apps/argocd.yaml` one minor version at a time, review `argocd app diff argocd`, then sync. Never run `helm upgrade` on Argo CD.

**Create a new service**
1. In Backstage: Create → Go service on the homelab.
2. Wait for the build workflow in the new repo to go green.
3. Merge the "Deploy <name>" pull request on this repo.
4. Open `http://<name>.localhost`.

The package can stay private; the pull secret and Image Updater handle it.

**Speed up Argo CD after a push** (it polls Git every three minutes):

```bash
kubectl -n argocd annotate app root argocd.argoproj.io/refresh=hard --overwrite
```

**Start the homelab after the Mac or OrbStack was stopped:**

```bash
./scripts/homelab-up.sh
```

It starts OrbStack and the k3d cluster, asks for the Vault unseal key if Vault is sealed, and re-syncs all secrets.
The cluster lives in OrbStack: if Docker Desktop is also installed, make sure the `orbstack` Docker context is active, or k3d reports `No nodes found`.

## Backing up Vault (planned)

Vault uses file storage, so backups are a copy of its encrypted data folder, taken from the Mac:

- `~/bin/vault-backup.sh` copies `vault/data` out of the `vault-0` pod into `~/Backups/vault/`, keeping the newest 14.
- A launchd job (`~/Library/LaunchAgents/com.homelab.vault-backup.plist`) runs it daily at 21:00.

### Restoring Vault

1. Let Argo CD deploy Vault. Do **not** run `vault operator init`.
2. Copy the backup in and restart Vault:
   ```bash
   kubectl -n vault exec -i vault-0 -- sh -c 'rm -rf /vault/data/* && tar xzf - -C /' < ~/Backups/vault/<backup-file>.tgz
   kubectl -n vault delete pod vault-0
   ```
3. Unseal with the existing key.
4. Force a sync and check: `kubectl annotate clustersecretstore vault force-sync=$(date +%s) --overwrite`, then `kubectl get externalsecret -A`.

## Known issues and fixes

**`yarn install` fails on a missing `got` patch.**
`@yarnpkg/core` 4.9.2 was published with a patch reference that only resolves inside Yarn's own repo.
Workaround: a placeholder patch at `.yarn/patches/got-npm-11.8.2-c1eb105458.patch` in the Backstage app.
It adds one text file and changes no code. Keep it committed with the app.

**Push to this repo is rejected.**
Image Updater committed in the meantime. Run `git pull` and push again.

**`InvalidImageName` on a pod.**
An image tag was set to a digest (`sha256:...`). Use the `sha-<commit>` tag instead.

**`ImagePullBackOff` on a service.**
The namespace lacks the `homelab/ghcr-pull: "true"` label, or the Deployment lacks `imagePullSecrets: [ghcr-pull]`.

**Image Updater doesn't update an app.**
Check its log. Common causes: a tag that doesn't match `^sha-[0-9a-f]{7}$`, wrong GHCR credentials, or a token without write access to this repo.

**Traefik returns 404 for a service hostname.**
No Ingress exists for that host yet: the pull request isn't merged, or Argo CD hasn't synced it.
Traefik can also take a short while to pick up a new Ingress.

**`no available server` from Traefik.**
The Ingress exists but no pod is ready behind it. Check the pod and its logs.

**Backstage stays `0/1` after a cluster start.**
If Backstage starts before Postgres accepts connections, it fails with `ECONNREFUSED` and does not retry.
Fixed with the `wait-for-postgres` init container in `charts/backstage/values.yaml`.
Manual fallback: `kubectl -n backstage rollout restart deploy/backstage`.

**`ClusterSecretStore` shows `InvalidProviderConfig`.**
The operator cannot log in to Vault. Vault is sealed, or the Kubernetes auth setup in step 5 is incomplete.
After fixing, force a re-check:
`kubectl annotate clustersecretstore vault force-sync=$(date +%s) --overwrite`

**`k3d cluster start` reports `No nodes found`.**
The active Docker context is not the runtime holding the cluster (for example Docker Desktop instead of OrbStack).
Run `docker context use orbstack`, start OrbStack, and try again. Never run `k3d cluster create` to fix this; it makes a new, empty cluster.

**`ExternalSecret` shows `SecretSyncedError` after a restart.**
Left over from sync attempts while Vault was sealed. After unsealing, force a re-sync, or run `./scripts/homelab-up.sh`.

**Vault is sealed after a cluster restart.**
Expected. Unseal it with the saved key.
Existing Kubernetes Secrets keep working while Vault is sealed; only new syncs wait.

**`Missing required config value at 'app.title'`.**
The chart loads only its own config unless told otherwise.
`values.yaml` passes `--config app-config.yaml` so the image's base config is loaded too.

**`Invalid type in config for key 'backend.listen'`.**
The chart sets the listen port as an object; `app-config.production.yaml` sets it as a string.
That file is therefore not loaded. Its settings are in `values.yaml` instead.

## Done

- k3d cluster with Traefik on localhost.
- Argo CD with an app-of-apps root Application, managing itself.
- Postgres and Backstage deployed through Git, all chart versions pinned.
- Backstage as a wrapper chart, with its values in this repo.
- Vault and External Secrets Operator; every secret comes from Vault.
- Backstage image built in GitHub Actions and pulled from GHCR.
- GitHub integration and GitHub-only sign-in.
- Kubernetes and Argo CD plugins in Backstage, both read-only.
- `go-service` software template: repo, image build, deployment pull request, image updater and catalog entry from one form.
- GHCR pull secret from Vault for every service namespace.
- Automatic image tag updates with Argo CD Image Updater.

## To do

- Set up and test the Vault backup and restore described above.
- Wire the `utility-delivery-labs` template to Kustomize, the pull secret and Image Updater.
- Optional: migrate Vault to Raft storage for consistent snapshots, or add auto-unseal.
