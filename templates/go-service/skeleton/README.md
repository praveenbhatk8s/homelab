# ${{ values.name }}

${{ values.description }}

Created from the `go-service` Backstage template.

- Image: `ghcr.io/praveenbhatk8s/${{ values.name }}`
- URL: http://${{ values.name }}.localhost
- Deployment: `manifests/${{ values.name }}/` in the `homelab` repo, synced by Argo CD

## Run locally

```bash
go run .
curl localhost:8080
```
