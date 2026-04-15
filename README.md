# TemonX IRP — Deploy

Production deployment for TemonX IRP — Intelligent Routing Platform for ISPs.

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/Lookin-Link/temonx-irp-deploy/main/setup.sh | sudo bash
```

## Requirements
- Ubuntu 22.04 / 24.04
- Docker 24+
- Docker Compose v2
- 4GB RAM minimum

## License Tiers

| Feature | Trial | Core | Standard | Professional | Enterprise |
|---|---|---|---|---|---|
| Links | 3 | 10 | 30 | 100 | Unlimited |
| Routers | 1 | 2 | 5 | 20 | Unlimited |
| AI Agent | ✗ | ✗ | ✗ | ✓ | ✓ |
| sFlow Analytics | ✗ | ✗ | ✗ | ✗ | ✓ |
| BGP Policy | ✗ | ✗ | ✓ | ✓ | ✓ |

Get a license: **https://temonx.io/pricing**

## Upgrade
```bash
cd /opt/temonx
docker compose pull && docker compose up -d
```
