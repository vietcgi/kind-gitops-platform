# Kong Ingress Routes - Demo Domain Setup

All platform services are exposed through Kong API Gateway using a unified domain: `demo.local`

## Accessing Services

### Kong Endpoint

Kong API Gateway is exposed via **LoadBalancer** with Cilium L2 announcements:
- **LoadBalancer IP**: From 172.18.1.0/24 pool (Docker bridge - reachable from host)
- **Service Type**: LoadBalancer with L2 announcements
- **Access**: Direct via LoadBalancer IP, no additional port mapping needed
- **Fallback**: NodePort also available at 172.18.0.2:32438 if needed

### Option 1: NodePort + Hosts File (Direct Access)

Add these entries to your `/etc/hosts` file:

```bash
# Kong routes via NodePort
172.18.0.2:32438 prometheus.demo.local
172.18.0.2:32438 grafana.demo.local
172.18.0.2:32438 loki.demo.local
172.18.0.2:32438 argocd.demo.local
172.18.0.2:32438 vault.demo.local
172.18.0.2:32438 harbor.demo.local
172.18.0.2:32438 jaeger.demo.local
172.18.0.2:32438 kong-admin.demo.local
```

**Note**: Since `/etc/hosts` doesn't support port syntax, you'll need to use:
```bash
# /etc/hosts
172.18.0.2 prometheus.demo.local
172.18.0.2 grafana.demo.local
... (other entries)

# Then access on port 32438:
http://grafana.demo.local:32438
```

### Option 2: Port Forward (Simplest for Local Development)

```bash
kubectl port-forward -n api-gateway svc/kong-kong-proxy 8000:80 8443:443 &

# Then access via localhost:
http://localhost:8000  (specify Host header or use Kong's request router)
```

### Option 3: Use curl with Host Headers

```bash
curl -H "Host: grafana.demo.local" http://172.18.0.2:32438/
```

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
- **Service Exposure**:
  - **KIND/Docker**: LoadBalancer with Cilium L2 (172.18.1.x)
  - **Production**: LoadBalancer with Cilium L2 (your network range)

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
