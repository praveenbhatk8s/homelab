# homelab

A local Kubernetes lab that runs a Backstage internal developer portal, deployed with GitOps.

Everything in the cluster except Argo CD itself is defined in this repo and applied by Argo CD.
Secret values are kept in Vault, not in Git.

## Stack

| Layer | Tool | Notes |
|---|---|---|
| Container runtime | Docker runtime on macOS (e.g. OrbStack) | Provides the Linux VM |
| Cluster | k3d running k3s | 1 server, 2 agents, cluster name `homelab` |
| Ingress | Traefik (bundled with k3s) | Ports 80/443 mapped to localhost |
| Storage | local-path (bundled with k3s) | Used by Postgres |
| GitOps | Argo CD | Installed with Helm, app-of-apps pattern |
| Database | PostgreSQL 17 | Plain StatefulSet, 2Gi volume |
| Portal | Backstage | Official Helm chart 2.10.2, locally built image |
| Secrets manager | HashiCorp Vault | Chart 0.34.1, standalone, 1Gi volume, manual unseal |
| Secrets sync | External Secrets Operator | Chart 2.12.0, logs in to Vault with Kubernetes auth |

## URLs

- Backstage: http://backstage.localhost (guest sign-in)
- Argo CD: http://argocd.localhost (user `admin`)
- Vault: http://vault.localhost

## How it fits together

1. **Git is the source of truth.** `bootstrap/root.yaml` is applied once by hand. It points Argo CD at `apps/`.
2. **Argo CD deploys everything in `apps/`.** Each file is one Application: Postgres, Backstage, Vault, External Secrets Operator and the secret store.
3. **Secrets never enter Git.** Values are stored in Vault. An `ExternalSecret` in Git names the Vault path, and the operator creates the Kubernetes Secret from it.
4. **Backstage reads its database login from that Secret** and waits for Postgres through an init container before starting.
5. **Traefik routes `*.localhost` hostnames** to Backstage, Argo CD and Vault.

Related repo: the Backstage app source is in `praveenbhatk8s/backstage`.

## Repository layout

```
bootstrap/root.yaml                  Root Application; the only manifest applied by hand
apps/postgres.yaml                   Argo CD Application for manifests/postgres
apps/vault.yaml                      Argo CD Application for the HashiCorp Vault Helm chart
apps/external-secrets.yaml           Argo CD Application for External Secrets Operator
apps/secret-store.yaml               Argo CD Application for manifests/secret-store
manifests/secret-store/cluster-secret-store.yaml  Connects External Secrets Operator to Vault
manifests/postgres/external-secret.yaml           Pulls postgres-credentials from Vault
apps/backstage.yaml                  Argo CD Application for the Backstage Helm chart (values inline)
manifests/postgres/statefulset.yaml  PostgreSQL StatefulSet
manifests/postgres/service.yaml      PostgreSQL Service
```

`root` watches `apps/`, so any Application added there is deployed automatically.
Both apps deploy into the `backstage` namespace with automated sync, prune and self-heal.

## Rebuilding from scratch

### 1. Tools

```bash
brew install orbstack k3d kubectl helm
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

### 4. Secrets (Vault + External Secrets Operator)

Secrets live in Vault. External Secrets Operator copies them into Kubernetes Secrets.
Git holds only the references (`ClusterSecretStore`, `ExternalSecret`), never the values.

After Argo CD has deployed the `vault` app, initialise it once:

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
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets ttl=1h
vault kv put secret/backstage/postgres POSTGRES_USER=backstage POSTGRES_PASSWORD='<password>'
```

Vault seals itself whenever its pod restarts. Unseal it again with the `vault operator unseal` command above.

Vault UI: http://vault.localhost

### 5. Backstage image

The Backstage app source lives in `praveenbhatk8s/backstage`. Clone it, then build it and load it into the cluster:

```bash
yarn install
yarn tsc
yarn build:backend
yarn build-image --tag backstage:dev
k3d image import backstage:dev -c homelab
```

The cluster sees this image as `docker.io/library/backstage:dev`.

### 6. Bootstrap GitOps

```bash
kubectl apply -f bootstrap/root.yaml
kubectl -n argocd get applications
kubectl -n backstage get pods
```

## Known issues and fixes

**`yarn install` fails on a missing `got` patch.**
`@yarnpkg/core` 4.9.2 was published with a patch reference that only resolves inside Yarn's own repo.
Workaround: a placeholder patch at `.yarn/patches/got-npm-11.8.2-c1eb105458.patch` in the Backstage app.
It adds one text file and changes no code. Keep it committed with the app.

**Backstage stays `0/1` after a cluster start.**
If Backstage starts before Postgres accepts connections, it fails with `ECONNREFUSED` and does not retry.
Fixed with the `wait-for-postgres` init container in `apps/backstage.yaml`.
Manual fallback: `kubectl -n backstage rollout restart deploy/backstage`.

**`ClusterSecretStore` shows `InvalidProviderConfig`.**
The operator cannot log in to Vault. Vault is sealed, or the Kubernetes auth setup in step 4 is incomplete.
After fixing, force a re-check:
`kubectl annotate clustersecretstore vault force-sync=$(date +%s) --overwrite`

**Vault is sealed after a cluster restart.**
Expected. Run `kubectl -n vault exec -it vault-0 -- vault operator unseal` with the saved unseal key.
Existing Kubernetes Secrets keep working while Vault is sealed; only new syncs wait.

**`Missing required config value at 'app.title'`.**
The chart loads only its own config unless told otherwise.
`apps/backstage.yaml` passes `--config app-config.yaml` so the image's base config is loaded too.

**`Invalid type in config for key 'backend.listen'`.**
The chart sets the listen port as an object; `app-config.production.yaml` sets it as a string.
That file is therefore not loaded. Its settings (URLs, database, catalog paths) are in `appConfig` instead.

**`no available server` from Traefik.**
The ingress exists but the Backstage pod is not ready. Check the pod and its logs.

## Done so far

- k3d cluster with Traefik on localhost.
- Argo CD with an app-of-apps root Application.
- Postgres and Backstage deployed through Git.
- All Helm chart versions pinned.
- Backstage waits for Postgres on startup.
- Vault and External Secrets Operator; `postgres-credentials` now comes from Vault.
- Backstage app in its own repo, including the `got` patch workaround.

## To do

- Build the Backstage image in GitHub Actions and push it to GHCR, replacing `k3d image import`.
- GitHub integration and sign-in for Backstage, with the token and OAuth secrets in Vault.
- Kubernetes plugin in Backstage.
- Argo CD plugin in Backstage.
- A software template that scaffolds a service repo and its Argo CD Application.
- Back up Vault data, or move to a hosted secrets manager, so secrets survive a cluster rebuild.
