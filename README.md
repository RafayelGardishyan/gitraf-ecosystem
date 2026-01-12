<p align="center">
  <img src="https://git.rafayel.dev/static/logo-header.png" alt="gitraf" width="400">
</p>

<p align="center">
  <strong>A lightweight, self-hosted git server ecosystem. Simple, fast, and free from corporate control.</strong>
</p>

<p align="center">
  <a href="https://git.rafayel.dev">Live Demo</a> •
  <a href="https://git.rafayel.dev/docs">Documentation</a>
</p>

---

Master repository for the gitraf self-hosted git server ecosystem. Contains all components as submodules.

**This project is maintained by a single developer and is provided as-is. While care is taken to ensure stability, bugs may exist. Contributions are always welcome!**

*Built with significant contributions from [Claude Code](https://claude.ai/claude-code).*

## Components

| Component | Description |
|-----------|-------------|
| [gitraf](gitraf/) | CLI tool for managing repositories |
| [gitraf-server](gitraf-server/) | Web interface for browsing repositories |
| [gitraf-pages](gitraf-pages/) | Static site hosting from git repos |
| [gitraf-deploy](gitraf-deploy/) | Interactive deployment script |
| [gitraf-infra](gitraf-infra/) | Kubernetes manifests and IaC |
| [gitraf-backup](https://git.rafayel.dev/gitraf-backup) | R2 backup system (optional module) |

## Quick Start

### Option 1: Interactive Script (VM/VPS)

Deploy on a fresh Ubuntu server:

```bash
curl -sSL https://raw.githubusercontent.com/RafayelGardishyan/gitraf-deploy/main/deploy.sh | sudo bash
```

### Option 2: Kubernetes (k3s)

Deploy using Kustomize:

```bash
# Clone gitraf-infra
git clone https://github.com/RafayelGardishyan/gitraf-infra.git
cd gitraf-infra

# Edit configs (replace placeholders with your values)
# See kubernetes/gitraf-server/configmap.yaml and kubernetes/nginx/configmap.yaml

# Deploy all components
kubectl apply -k kubernetes/base/
```

See [gitraf-infra](gitraf-infra/) for detailed Kubernetes deployment instructions.

## Features

- **No dependencies** on GitHub, GitLab, or any cloud provider
- **Tailscale integration** for secure private access
- **Optional public access** for open source projects
- **Static site hosting** - deploy sites from repos to `{repo}.yourdomain.com`
- **Git LFS support** with S3-compatible storage
- **GitHub mirroring** - automatic sync to GitHub with SSH key management
- **Submodule support** - full display with commit hash, URL, and external links
- **Rate limiting** - nginx-level protection against abuse
- **One-click updates** - update server from the web interface
- **Lightweight** - runs on a small VPS with minimal resources
- **R2 Backup** - optional nightly sync to Cloudflare R2 (VM or Kubernetes CronJob)

## Clone with Submodules

```bash
git clone --recursive https://github.com/RafayelGardishyan/gitraf-ecosystem.git
```

Or if you already cloned:

```bash
git submodule update --init --recursive
```

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  gitraf CLI     │────▶│  SSH/HTTPS      │────▶│  ogit server    │
│  (client)       │     │                 │     │  (git hosting)  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                        ┌───────────────────────────────┼───────────────────────────────┐
                        │                               │                               │
                        ▼                               ▼                               ▼
                ┌─────────────────┐             ┌─────────────────┐             ┌─────────────────┐
                │  gitraf-server  │             │  gitraf-pages   │             │  Git LFS        │
                │  (web UI)       │             │  (static sites) │             │  (S3 storage)   │
                └─────────────────┘             └─────────────────┘             └─────────────────┘
```

## License

MIT

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests to the individual component repositories.

## Acknowledgments

This project was built with significant contributions from [Claude Code](https://claude.ai/claude-code), Anthropic's AI coding assistant.
