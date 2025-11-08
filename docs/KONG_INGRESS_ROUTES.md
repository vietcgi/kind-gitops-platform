# Kong Ingress Routes - Demo Domain Setup

All platform services are exposed through Kong API Gateway using a unified domain: `demo.local`

## Accessing Services

### Configure Local Hosts File

Add these entries to your `/etc/hosts` file:

```bash
# Kong Ingress Routes
127.0.0.1 prometheus.demo.local
127.0.0.1 grafana.demo.local
127.0.0.1 loki.demo.local
127.0.0.1 argocd.demo.local
127.0.0.1 vault.demo.local
127.0.0.1 harbor.demo.local
127.0.0.1 jaeger.demo.local
127.0.0.1 kong-admin.demo.local
```

**Or use `localhost` (127.0.0.1) for local development.**

### Service Endpoints

| Service | URL | Description |
|---------|-----|-------------|
| Prometheus | http://prometheus.demo.local | Metrics collection & visualization |
| Grafana | http://grafana.demo.local | Dashboards (admin/prom-operator) |
| Loki | http://loki.demo.local | Log aggregation API |
| ArgoCD | http://argocd.demo.local | GitOps management (admin/<password>) |
| Vault | http://vault.demo.local | Secrets management |
| Harbor | http://harbor.demo.local | Container registry |
| Jaeger | http://jaeger.demo.local | Distributed tracing |
| Kong Admin | http://kong-admin.demo.local | Kong API Gateway management |

## Port Forwarding (If hosts file not configured)

For local development without modifying hosts file, use port-forwarding:

```bash
# Kong LoadBalancer (requires external IP, or use port-forward)
kubectl port-forward -n api-gateway svc/kong-kong-proxy 8000:80 &

# Then access services via:
# http://localhost:8000/prometheus
# http://localhost:8000/grafana
# etc.
```

## Kong Configuration

- **Ingress Class**: `kong`
- **Domain Pattern**: `<service>.demo.local`
- **API Gateway**: Kong (v2.x)
- **Load Balancer IP**: Pending (see Cilium LoadBalancer setup)

## Setting Custom Domain

To use a different domain (e.g., `platform.local`, `company.com`), edit the ingress routes:

```bash
kubectl patch ingress prometheus-ingress -n monitoring -p '{"spec":{"rules":[{"host":"prometheus.company.com"}]}}'
```

Or re-apply the manifests with your preferred domain.

## Kong Admin API

Access Kong's admin API for advanced configuration:

```bash
curl http://kong-admin.demo.local/
```

Common admin endpoints:
- `GET /` - Kong status
- `GET /services` - List services
- `GET /routes` - List routes
- `GET /upstreams` - List upstream pools
