# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Minecraft Bedrock Dedicated Server management system for home Linux servers. Provides configurable scripts for installation, backups, auto-updates, and monitoring, packaged as a GitHub release that users install via `curl | tar | install.sh`.

## Project Structure

- `scripts/` - Server management scripts (sourced by systemd/cron, all use `scripts/lib.sh` for shared config/logging/notification functions)
- `templates/` - Systemd service and crontab templates with `%%VARIABLE%%` placeholders replaced at install time
- `install.sh` - Installer that creates user, downloads Bedrock server, installs scripts/service/cron
- `config.env.example` - Configuration template with all supported variables
- `tests/` - Vagrant-based integration tests (Ubuntu 22.04 VM)
- `.github/workflows/release.yml` - Packages and releases on `v*` tag push with build provenance attestation

## Key Design Decisions

- **Config-driven**: All paths, names, schedules, etc. come from `config.env` (no hardcoded values in scripts)
- **Update URL**: Microsoft moved the Bedrock download link behind JavaScript. Scripts use the API at `https://net-secondary.web.minecraft-services.net/api/v1.0/download/links` with jq (preferred) or grep fallback
- **Service user**: Runs as a dedicated `minecraft` system user with sudoers entry for `systemctl stop/start/restart minecraft` only
- **Screen session**: Server runs inside GNU screen (named `minecraft`) for console access; systemd uses `Type=forking`
- **Backup rotation**: Keeps N most recent backups by modification time, prunes excess

## Testing

```bash
cd tests
vagrant up
vagrant ssh -c "sudo /vagrant/tests/run_tests.sh"
vagrant destroy
```

Tests cover: installation, systemd service lifecycle, backup creation/rotation, and update URL extraction.

## Releasing

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions packages `scripts/`, `templates/`, `install.sh`, `config.env.example`, and `LICENSE` into a tarball, signs it with build provenance, and creates a GitHub release.
