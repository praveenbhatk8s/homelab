# homelab

A local Kubernetes lab that runs a Backstage internal developer portal, deployed with GitOps.

Everything in the cluster except Argo CD itself is defined in this repo and applied by Argo CD.
Secret values are kept in Vault, never in Git.

## Stack

| Layer | Tool | Notes |
|---|---|---|
| Container runtime | Docker runtime on macOS (e.g. OrbStack) | Provides the Linux VM |
| Cluster | k3d running k3s | 1 server, 2 agents, cluster name `homelab` |
| Ingress | Traefik (bundled with k3s) | Ports 80/443 mapped to localhost |
| Storage | local-path (bundled with k3s) | Used by Postgres and Vault |
| GitOps | Argo CD | Installed with Helm, app-of-apps pattern |
| Database | PostgreSQL 17 | Plain StatefulSet, 2Gi volume |
| Portal | Backstage | Helm chart 2.10.2, image built in GitHub Actions and pulled from GHCR |
| Secrets manager | HashiCorp Vault | Chart 0.34.1, standalone, 1Gi volume, manual unseal |
| Secrets sync | External Secrets Operator | Chart 2.12.0, logs in to Vault with Kubernetes auth |

## URLs

- Backstage: http://backstage.localhost (GitHub sign-in; guest still enabled)
- Argo CD: http://argocd.localhost (user `admin`)
- Vault: http://vault.localhost
- Services created from the template: http://<name>.localhost

## How it fits together

1. **Git is the source of truth.** `bootstrap/root.yaml` is applied once by hand. It points Argo CD at `apps/`.
2. **Argo CD deploys everything in `apps/`.** Each file is one Application.
3. **Secrets never enter Git.** Values are stored in Vault. An `ExternalSecret` in Git names the Vault path, and External Secrets Operator creates the Kubernetes Secret from it.
4. **The Backstage image is built by CI.** A push to `praveenbhatk8s/backstage` builds an arm64 image and pushes it to `ghcr.io/praveenbhatk8s/backstage` with a `sha-<commit>` tag. Deploying a new build means changing that tag in `apps/backstage.yaml`.
5. **Backstage connects to everything else:**
   - GitHub, with a token for the catalog and scaffolder, and OAuth for sign-in.
   - The cluster, through its own read-only service account (Kubernetes tab).
   - Argo CD, through a read-only API account (sync and health per component).
6. **The golden path.** The `go-service` template creates a service repo, opens a pull request on this repo with its Argo CD Application, and registers the service in the catalog. Merging the pull request deploys it.
7. **Traefik routes `*.localhost` hostnames** to Backstage, Argo CD, Vault and every templated service.

Related repos:
- `praveenbhatk8s/backstage`: the Backstage app source and its image build workflow.
- One repo per service created from the template, for example `praveenbhatk8s/hello`.

## Repository layout

```
bootstrap/root.yaml                    Root Application; the only manifest applied by hand

apps/postgres.yaml                     Postgres, from manifests/postgres
apps/backstage.yaml                    Backstage Helm chart; all Backstage config is inline here
apps/backstage-secrets.yaml            Backstage's ExternalSecrets, from manifests/backstage-secrets
apps/backstage-rbac.yaml               Backstage's read-only cluster access, from manifests/backstage-rbac
apps/vault.yaml                        HashiCorp Vault Helm chart
apps/external-secrets.yaml             External Secrets Operator Helm chart
apps/secret-store.yaml                 Vault connection, from manifests/secret-store
apps/<service>.yaml                    One per templated service, added by its pull request

manifests/postgres/                    StatefulSet, Service, ExternalSecret for postgres-credentials
manifests/backstage-secrets/github.yaml  GitHub token and OAuth credentials from Vault
manifests/backstage-secrets/argocd.yaml  Argo CD API token from Vault
manifests/backstage-rbac/rbac.yaml     Read-only ClusterRole and binding for the backstage service account
manifests/secret-store/                ClusterSecretStore pointing at Vault
manifests/<service>/                   Deployment, Service, Ingress per templated service

templates/go-service/template.yaml     The Backstage software template
templates/go-service/skeleton/         Files for the new service repo
templates/go-service/gitops/           Files for the pull request on this repo
```

All Applications use automated sync with prune and self-heal.

## Secrets in Vault

| Vault path | Keys | Kubernetes Secret | Used by |
|---|---|---|---|
| `secret/backstage/postgres` | `POSTGRES_USER`, `POSTGRES_PASSWORD` | `backstage/postgres-credentials` | Postgres, Backstage |
| `secret/backstage/github` | `GITHUB_TOKEN`, `AUTH_GITHUB_CLIENT_ID`, `AUTH_GITHUB_CLIENT_SECRET` | `backstage/backstage-github` | Backstage integration and sign-in |
| `secret/backstage/argocd` | `ARGOCD_AUTH_TOKEN` | `backstage/backstage-argocd` | Backstage Argo CD plugin |

Kept outside the cluster, in a password manager: the Vault unseal key and root token.

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

### 3. Argo CD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  -n argocd --create-namespace \
  --set global.domain=argocd.localhost \
  --set server.ingress.enabled=true \
  --set server.ingress.ingressClassName=traefik \
  --set 'configs.params.server\.insecure=true'

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Add the read-only `backstage` account used by the Argo CD plugin:

```bash
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"accounts.backstage":"apiKey"}}'
kubectl -n argocd patch configmap argocd-rbac-cm --type merge -p '{"data":{"policy.csv":"g, backstage, role:readonly"}}'
```

### 4. Bootstrap GitOps

```bash
kubectl apply -f bootstrap/root.yaml
kubectl -n argocd get applications
```

Vault comes up sealed, and Backstage waits for its secrets until steps 5 and 6 are done.

### 5. Vault

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
- A GitHub personal access token (classic) with `repo` and `workflow` scopes.
- A GitHub OAuth app with homepage `http://backstage.localhost` and callback `http://backstage.localhost/api/auth/github/handler/frame`.
- An Argo CD token: `argocd login argocd.localhost --plaintext --grpc-web --username admin`, then `argocd account generate-token --account backstage`.

Inside the Vault pod:

```sh
vault kv put secret/backstage/postgres POSTGRES_USER=backstage POSTGRES_PASSWORD='<password>'
vault kv put secret/backstage/github GITHUB_TOKEN='<token>' AUTH_GITHUB_CLIENT_ID='<id>' AUTH_GITHUB_CLIENT_SECRET='<secret>'
vault kv put secret/backstage/argocd ARGOCD_AUTH_TOKEN='<token>'
```

Check that everything synced:

```bash
kubectl get clustersecretstore vault
kubectl -n backstage get externalsecret
```

### 7. Backstage

The image comes from GHCR, so nothing needs building locally. If Backstage started before its secrets existed, restart it:

```bash
kubectl -n backstage rollout restart deploy/backstage
```

## Day-to-day

**Release a new Backstage build**
1. Push to `main` in `praveenbhatk8s/backstage` and wait for the workflow to go green.
2. Get the tag: `echo "sha-$(git rev-parse --short=7 origin/main)"`.
3. Set it in `apps/backstage.yaml`, commit and push.

**Create a new service**
1. In Backstage: Create → Go service on the homelab.
2. Wait for the build workflow in the new repo to go green.
3. Make the new GHCR package public (profile → Packages → the package → Package settings).
4. Merge the "Deploy <name>" pull request on this repo.
5. Open `http://<name>.localhost`.

**Speed up Argo CD after a push** (it polls Git every three minutes):

```bash
kubectl -n argocd annotate app root argocd.argoproj.io/refresh=hard --overwrite
```

**After a cluster restart:** unseal Vault with `kubectl -n vault exec -it vault-0 -- vault operator unseal`.

## Known issues and fixes

**`yarn install` fails on a missing `got` patch.**
`@yarnpkg/core` 4.9.2 was published with a patch reference that only resolves inside Yarn's own repo.
Workaround: a placeholder patch at `.yarn/patches/got-npm-11.8.2-c1eb105458.patch` in the Backstage app.
It adds one text file and changes no code. Keep it committed with the app.

**`InvalidImageName` on the Backstage pod.**
The image `tag` was set to a digest (`sha256:...`). Use the `sha-<commit>` tag from the build instead.

**`ImagePullBackOff` on a new service.**
The GHCR package is private. Make it public, or add a pull secret.

**Traefik returns 404 for a service hostname.**
No Ingress exists for that host yet: the pull request is not merged, or Argo CD has not synced it.
Traefik can also take a short while to pick up a new Ingress.

**`no available server` from Traefik.**
The Ingress exists but no pod is ready behind it. Check the pod and its logs.

**Backstage stays `0/1` after a cluster start.**
If Backstage starts before Postgres accepts connections, it fails with `ECONNREFUSED` and does not retry.
Fixed with the `wait-for-postgres` init container in `apps/backstage.yaml`.
Manual fallback: `kubectl -n backstage rollout restart deploy/backstage`.

**`ClusterSecretStore` shows `InvalidProviderConfig`.**
The operator cannot log in to Vault. Vault is sealed, or the Kubernetes auth setup in step 5 is incomplete.
After fixing, force a re-check:
`kubectl annotate clustersecretstore vault force-sync=$(date +%s) --overwrite`

**Vault is sealed after a cluster restart.**
Expected. Unseal it with the saved key.
Existing Kubernetes Secrets keep working while Vault is sealed; only new syncs wait.

**`Missing required config value at 'app.title'`.**
The chart loads only its own config unless told otherwise.
`apps/backstage.yaml` passes `--config app-config.yaml` so the image's base config is loaded too.

**`Invalid type in config for key 'backend.listen'`.**
The chart sets the listen port as an object; `app-config.production.yaml` sets it as a string.
That file is therefore not loaded. Its settings are in `appConfig` instead.

## Done

- k3d cluster with Traefik on localhost.
- Argo CD with an app-of-apps root Application.
- Postgres and Backstage deployed through Git, all chart versions pinned.
- Backstage waits for Postgres on startup.
- Vault and External Secrets Operator; all Backstage secrets come from Vault.
- Backstage app in its own repo; image built in GitHub Actions and pulled from GHCR.
- GitHub integration and GitHub sign-in.
- Kubernetes plugin, using Backstage's own read-only service account.
- Argo CD plugin, using a read-only Argo CD account.
- `go-service` software template: repo, image build, deployment pull request and catalog entry from one form.

## To do

- GHCR pull secret from Vault, so new services don't need their package made public.
- Automatic image tag updates (Argo CD Image Updater, or a workflow that commits the new tag here).
- Remove guest sign-in.
- Back up Vault data, or set up auto-unseal.
- Manage Argo CD itself through GitOps, so its settings survive a `helm upgrade`.
