# homelab

A local Kubernetes lab that runs a Backstage internal developer portal, deployed with GitOps.

Everything in the cluster except Argo CD itself and one secret is defined in this repo and applied by Argo CD.

## Stack

| Layer | Tool | Notes |
|---|---|---|
| Container runtime | Docker runtime on macOS (e.g. OrbStack) | Provides the Linux VM |
| Cluster | k3d running k3s | 1 server, 2 agents, cluster name `homelab` |
| Ingress | Traefik (bundled with k3s) | Ports 80/443 mapped to localhost |
| Storage | local-path (bundled with k3s) | Used by Postgres |
| GitOps | Argo CD | Installed with Helm, app-of-apps pattern |
| Database | PostgreSQL 17 | Plain StatefulSet, 2Gi volume |
| Portal | Backstage | Official Helm chart, locally built image |

## URLs

- Backstage: http://backstage.localhost (guest sign-in)
- Argo CD: http://argocd.localhost (user `admin`)

## Repository layout

```
bootstrap/root.yaml                  Root Application; the only manifest applied by hand
apps/postgres.yaml                   Argo CD Application for manifests/postgres
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

### 4. Database secret

Not stored in Git. Create it before the apps sync:

```bash
kubectl create namespace backstage
kubectl -n backstage create secret generic postgres-credentials \
  --from-literal=POSTGRES_USER=backstage \
  --from-literal=POSTGRES_PASSWORD='<password>'
```

### 5. Backstage image

The Backstage app source lives outside this repo. Build it and load it into the cluster:

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
Fix: `kubectl -n backstage rollout restart deploy/backstage`.

**`Missing required config value at 'app.title'`.**
The chart loads only its own config unless told otherwise.
`apps/backstage.yaml` passes `--config app-config.yaml` so the image's base config is loaded too.

**`Invalid type in config for key 'backend.listen'`.**
The chart sets the listen port as an object; `app-config.production.yaml` sets it as a string.
That file is therefore not loaded. Its settings (URLs, database, catalog paths) are in `appConfig` instead.

**`no available server` from Traefik.**
The ingress exists but the Backstage pod is not ready. Check the pod and its logs.

## To do

- Pin the Backstage chart version (currently `targetRevision: "*"`).
- Add an init container so Backstage waits for Postgres.
- Manage `postgres-credentials` in Git with Sealed Secrets.
- Put the Backstage app in its own repo and push images to GHCR instead of `k3d image import`.
- Add the Argo CD and Kubernetes plugins to Backstage.
- Add a software template that scaffolds a service repo and its Argo CD Application.
- Replace guest sign-in with GitHub auth.
