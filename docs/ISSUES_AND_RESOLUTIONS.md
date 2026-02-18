# Deployment Issues and Resolutions

This document documents all issues encountered during the deployment process and how they were resolved.

## Issue 1: k3d Cluster Not Running

**Error:**
```
The connection to the server 0.0.0.0:52364 was refused - did you specify the right host or port?
```

**Cause:** The k3d cluster was stopped.

**Resolution:**
```bash
k3d cluster start go-ms-local
```

**Status:** ✅ Resolved

---

## Issue 2: Port 8080 Already in Use

**Error:**
```
Error response from daemon: Ports are not available: exposing port TCP 0.0.0.0:8080 -> 0.0.0.0:0: listen tcp 0.0.0.0:8080: bind: address already in use
```

**Cause:** A `server` process (the Go book-service binary) was running on port 8080.

**Resolution:**
```bash
# Find the process
lsof -i :8080

# Kill it
kill 4806

# Then start the cluster
k3d cluster start go-ms-local
```

**Status:** ✅ Resolved

---

## Issue 3: Kustomize Patch Path Error

**Error:**
```
error: replace operation does not apply: doc is missing path: /spec/resources/requests/memory: missing value
```

**Cause:** The JSON patch paths in the production overlay were incorrect. They were targeting `/spec/resources/*` instead of the correct nested path for containers.

**Resolution:**

Updated `k8s/overlays/production/kustomization.yaml`:

```yaml
# Before (incorrect):
path: /spec/resources/requests/memory

# After (correct):
path: /spec/template/spec/containers/0/resources/requests/memory
```

Full correct paths:
- `/spec/template/spec/containers/0/resources/requests/memory`
- `/spec/template/spec/containers/0/resources/requests/cpu`
- `/spec/template/spec/containers/0/resources/limits/memory`
- `/spec/template/spec/containers/0/resources/limits/cpu`

**Status:** ✅ Resolved

---

## Issue 4: Docker Image Pull Error - 401 Unauthorized

**Error:**
```
Failed to pull image "ghcr.io/gauravv-dev/go-ms:latest": failed to resolve reference: 401 Unauthorized
```

**Cause:** The k3d cluster couldn't pull from the private GitHub Container Registry without authentication.

**Resolution:**

Created a docker-registry secret:

```bash
kubectl create secret docker-registry ghcr-pull-secret -n go-ms \
  --docker-server=ghcr.io \
  --docker-username=gauravv-dev \
  --docker-password=YOUR_GITHUB_PAT
```

Patched the deployment to use the secret:

```bash
kubectl patch deployment go-ms -n go-ms \
  -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-pull-secret"}]}}}}'
```

Rolled out the deployment:

```bash
kubectl rollout restart deployment/go-ms -n go-ms
```

**Status:** ✅ Resolved

---

## Issue 5: Domain Access Not Working

**Error:**
```
curl: (52) Empty reply from server
```

When accessing via:
```bash
curl -H "Host: dev-go-ms-api.gauravv.dev" http://localhost:8080/health
```

**Cause:** The k3d LoadBalancer was routing traffic to port 80 on the k3d nodes, but the Istio gateway was accessible via NodePort 32705, which was not exposed on the host.

**Root Cause Analysis:**
1. Istio ingress gateway service exposes NodePort 32705 for HTTP
2. k3d's nginx LoadBalancer only exposed ports 80, 443, and 6443
3. Traffic to localhost:8080 went to nginx → k3d node port 80 → nowhere

**Resolution:**

Created a custom nginx configuration to expose the Istio NodePorts:

1. Created `/Users/gaurav.verma/Work/repos/glm4-7/go-ms/tmp/nginx.conf`:

```nginx
stream {
    upstream 80_tcp {
        server k3d-go-ms-local-agent-0:80 max_fails=1 fail_timeout=10s;
        server k3d-go-ms-local-server-0:80 max_fails=1 fail_timeout=10s;
    }
    server {
        listen        80;
        proxy_pass    80_tcp;
        proxy_timeout 600;
        proxy_connect_timeout 2s;
    }
    # ... other ports ...
    upstream 32705_tcp {
        server k3d-go-ms-local-agent-0:32705 max_fails=1 fail_timeout=10s;
        server k3d-go-ms-local-server-0:32705 max_fails=1 fail_timeout=10s;
    }
    server {
        listen        32705;
        proxy_pass    32705_tcp;
        proxy_timeout 600;
        proxy_connect_timeout 2s;
    }
}

events {
    worker_connections 1024;
}
```

2. Recreated the k3d serverlb container with NodePort exposed:

```bash
docker stop k3d-go-ms-local-serverlb
docker rm k3d-go-ms-local-serverlb
docker run -d --name k3d-go-ms-local-serverlb \
  --network k3d-go-ms-local \
  --restart always \
  -p 8080:80 \
  -p 8443:443 \
  -p 52364:6443 \
  -p 32705:32705 \
  -v /Users/gaurav.verma/Work/repos/glm4-7/go-ms/tmp/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine
```

**Test command:**
```bash
curl -H "Host: dev-go-ms-api.gauravv.dev" -H "X-API-Key: prod-key-123" http://localhost:32705/health
```

**Status:** ✅ Resolved - HTTP working via NodePort 32705

---

## Issue 6: HTTPS Access Not Working

**Error:**
```
curl: (35) SSL handshake error
```

When accessing via:
```bash
curl -k -H "Host: dev-go-ms-api.gauravv.dev" https://localhost:8443/health
```

**Cause:** The k3d LoadBalancer port 8443 routes to port 443 in the cluster, but the Istio HTTPS NodePort 30884 was not exposed on the host.

**Resolution Attempted:**

1. Added HTTPS NodePort 30884 to nginx configuration:

```nginx
upstream 30884_tcp {
    server k3d-go-ms-local-agent-0:30884 max_fails=1 fail_timeout=10s;
    server k3d-go-ms-local-server-0:30884 max_fails=1 fail_timeout=10s;
}
server {
    listen        30884;
    proxy_pass    30884_tcp;
    proxy_timeout 600;
    proxy_connect_timeout 2s;
}
```

2. Recreated container with port 30884 exposed:

```bash
docker run -d --name k3d-go-ms-local-serverlb \
  --network k3d-go-ms-local \
  --restart always \
  -p 8080:80 \
  -p 8443:443 \
  -p 52364:6443 \
  -p 32705:32705 \
  -p 30884:30884 \
  -v /Users/gaurav.verma/Work/repos/glm4-7/go-ms/tmp/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine
```

**Status:** ⏳ In Progress - Configuration complete, not yet tested

---

## Issue 7: nginx Container Restart Loop

**Error:**
```
2026/02/17 13:46:01 [emerg] 1#1: "stream" directive is not allowed here in /etc/nginx/conf.d/default.conf:1
```

**Cause:** The `stream` directive was placed in `/etc/nginx/conf.d/default.conf`, but stream blocks must be in the main `nginx.conf` file, not in conf.d.

**Resolution:**

Modified the approach to write to `/etc/nginx/nginx.conf` directly:

```bash
docker run -d --name k3d-go-ms-local-serverlb \
  -v /path/to/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine
```

Ensured the config file has:
```nginx
stream {
    # stream blocks here
}

events {
    worker_connections 1024;
}
```

**Status:** ✅ Resolved

---

## Issue 8: Understanding Localhost + Domain Name in Request

**Question:** Why do I need both `localhost` and the domain name?

```bash
curl -H "Host: dev-go-ms-api.gauravv.dev" http://localhost:32705/health
```

**Explanation:**

- `localhost:32705` - The actual destination (IP:PORT where traffic is sent)
- `Host: dev-go-ms-api.gauravv.dev` - The virtual host header for Istio routing

This is a **local development quirk**:
1. k3d runs locally → accessed via `localhost`
2. Port 32705 is the exposed NodePort
3. Istio VirtualService uses `Host` header to route to the correct service

**In production**, you would use:
```bash
curl https://dev-go-ms-api.gauravv.dev/health
```

The domain would resolve to the LoadBalancer IP automatically.

**Workaround for local:**
```bash
# Use domain from /etc/hosts
curl http://dev-go-ms-api.gauravv.dev:32705/health
```

**Status:** ✅ Explained - Not a bug, expected behavior for local k3d

---

## Summary of Issues

| Issue | Status | Impact |
|-------|--------|--------|
| k3d cluster not running | ✅ Resolved | Blocked deployment |
| Port 8080 conflict | ✅ Resolved | Blocked cluster start |
| Kustomize patch paths | ✅ Resolved | Blocked deployment apply |
| Image pull 401 | ✅ Resolved | Pods couldn't start |
| Domain access HTTP | ✅ Resolved | Istio gateway not accessible |
| HTTPS access | ⏳ In Progress | To be tested |
| nginx restart loop | ✅ Resolved | LoadBalancer not working |
| Localhost + domain confusion | ✅ Explained | User understanding |

## Key Learnings

1. **k3d Limitations:** Local k3d clusters don't automatically expose NodePorts on the host
2. **Istio + k3d:** Requires custom nginx configuration to expose Istio NodePorts
3. **Private Registry:** Requires image pull secrets in Kubernetes
4. **Kustomize Paths:** Must include full path to container resources (`/spec/template/spec/containers/0/*`)
5. **Local Development:** Domain routing via `Host` header is different from production DNS
