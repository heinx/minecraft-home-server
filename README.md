# Minecraft Home Server

Easy-to-install Minecraft Bedrock Dedicated Server for home Linux (Ubuntu) servers. Runs reliably with automatic updates, backups, and monitoring.

## Prerequisites

Ubuntu server with:

```bash
sudo apt-get install curl unzip zip screen
```

Optional: `jq` (better update URL parsing), `msmtp` (email notifications).

## Quick Install

```bash
# Replace v1.0.0 with the desired version
VERSION=v1.0.0
curl -sLO "https://github.com/heinx/minecraft-home-server/releases/download/${VERSION}/minecraft-home-server-${VERSION}.tar.gz"
```

### Verify the download

Each release package is built from a git tag by GitHub Actions. You can verify that the package is authentic and inspect what's in it before installing:

```bash
gh attestation verify "minecraft-home-server-${VERSION}.tar.gz" --repo heinx/minecraft-home-server
```

A successful verification looks like:

```
Loaded digest sha256:abc123... for file minecraft-home-server-v1.0.0.tar.gz
Loaded 1 attestation from GitHub API
✓ Verification succeeded!

   - Predicate type: https://slsa.dev/provenance/v1
   - Signer:         https://github.com/heinx/minecraft-home-server/.github/workflows/release.yml@refs/tags/v1.0.0
   - Build trigger:  push
   - Source:         https://github.com/heinx/minecraft-home-server
```

The **Signer** field confirms the package was built by this repo's release workflow at the exact tag version. You can inspect the source code for any tag on GitHub:
`https://github.com/heinx/minecraft-home-server/tree/<version>`

### Install

```bash
tar xzf "minecraft-home-server-${VERSION}.tar.gz"
cd "minecraft-home-server-${VERSION}"
sudo ./install.sh
```

The installer prompts for server name, world name, ports, etc. For non-interactive installs, provide a config file:

```bash
sudo ./install.sh --config /path/to/config.env
```

## What it does

- Runs Bedrock Dedicated Server as a systemd service (auto-start on boot, auto-restart on crash)
- Nightly world backups with configurable retention (default: 20)
- Automatic server updates via [Microsoft's Minecraft services API](https://net-secondary.web.minecraft-services.net/api/v1.0/download/links) (`minecraft-services.net` — registered to Microsoft Corporation, TLS certificate issued by Microsoft CA)
- Email notifications on failures (update, backup, or server crash)

## Import an existing world

Set these in your `config.env` before installing:

```bash
IMPORT_WORLD="/path/to/your/world"           # directory or .zip
IMPORT_SERVER_PROPERTIES="/path/to/server.properties"  # optional
```

## Post-install: Email notifications

These steps can be done at any time after installation.

Get notified when a backup fails, an update fails, or the server can't start. Requires a mail transport agent on the server — `msmtp` is recommended.

1. Install msmtp:
   ```bash
   sudo apt-get install msmtp msmtp-mta
   ```

2. Configure msmtp (e.g. with Gmail SMTP). Create `/etc/msmtprc`:
   ```
   account default
   host smtp.gmail.com
   port 587
   tls on
   auth on
   user your-email@gmail.com
   password your-app-password
   from your-email@gmail.com
   ```
   ```bash
   sudo chmod 600 /etc/msmtprc
   ```
   For Gmail, use an [App Password](https://support.google.com/accounts/answer/185833) (not your regular password).

3. Enable notifications in `config.env`:
   ```bash
   sudo nano /opt/minecraft-bedrock/config.env
   ```
   ```bash
   NOTIFY_ENABLED=true
   NOTIFY_EMAIL="your-email@gmail.com"
   ```

4. Test it:
   ```bash
   echo "Test notification" | msmtp your-email@gmail.com
   ```

The scripts also support `sendmail` or `mail` if already configured on the system.

To verify that the update cron job and email delivery are working, temporarily enable verbose update notifications:

```bash
NOTIFY_ON_UPDATE_CHECK=true
```

This sends an email on every update check (not just failures). Disable it once you've confirmed emails are arriving.

Example notification emails:

```
Subject: Minecraft Update Successful
Server updated to bedrock-server-1.26.10.4.zip and is running.
```

```
Subject: Minecraft Update Check
Server is already up to date (bedrock-server-1.26.10.4.zip)
```

```
Subject: Minecraft Update Failed
Server did not start after updating to bedrock-server-1.26.10.4.zip
```

```
Subject: Minecraft Backup Failed
Failed to zip world 'MyWorld'
```

## Logs

Server and management logs are in `INSTALL_DIR/logs/`:

```bash
# Live server output
tail -f /opt/minecraft-bedrock/logs/server.log

# Backup history
tail -f /opt/minecraft-bedrock/logs/backup.log

# Update history
tail -f /opt/minecraft-bedrock/logs/update.log

# Systemd journal
journalctl -u minecraft -f
```

Logs are preserved across server updates.

## Managing the server

```bash
systemctl status minecraft      # Check status
systemctl stop minecraft        # Stop
systemctl start minecraft       # Start
systemctl restart minecraft     # Restart
journalctl -u minecraft -f      # Follow logs

# Attach to server console (detach with Ctrl-A, D)
sudo -u minecraft screen -r minecraft
```

## Configuration

All configuration lives in `config.env` at the install directory (default: `/opt/minecraft-bedrock/config.env`). See [config.env.example](config.env.example) for all options.

Key settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVER_NAME` | `Minecraft Server` | Server name shown to players |
| `WORLD_NAME` | `world` | World directory name |
| `INSTALL_DIR` | `/opt/minecraft-bedrock` | Installation path |
| `BACKUP_DIR` | `/opt/minecraft-bedrock/backups` | Backup storage path |
| `BACKUP_KEEP_COUNT` | `20` | Number of backups to retain |
| `BACKUP_CRON` | `15 3 * * *` | Backup schedule (cron syntax) |
| `UPDATE_CRON` | `15 4 * * *` | Update check schedule |
| `NOTIFY_ENABLED` | `false` | Enable email notifications |
| `NOTIFY_EMAIL` | | Email address for notifications |
| `NOTIFY_ON_UPDATE_CHECK` | `false` | Email on every update check (for testing) |

## Manual operations

```bash
# Run a backup manually
sudo -u minecraft /opt/minecraft-bedrock/scripts/backup.sh

# Check for updates manually
sudo -u minecraft /opt/minecraft-bedrock/scripts/update.sh

# Restore from a backup
sudo /opt/minecraft-bedrock/scripts/restore.sh /opt/minecraft-bedrock/backups/world_2025_01_01-120000.zip
```

## Architecture

```
/opt/minecraft-bedrock/           # INSTALL_DIR
  bedrock_server                  # Mojang's server binary
  server.properties               # Server configuration
  config.env                      # Management scripts configuration
  worlds/                         # World data
  scripts/                        # Management scripts
    lib.sh                        # Shared functions (logging, config, notifications)
    start.sh                      # Start server in screen session
    stop.sh                       # Graceful stop via screen
    backup.sh                     # World backup + rotation + offsite sync
    update.sh                     # Auto-update from Microsoft API
    restore.sh                    # Restore world from backup
  logs/                           # server.log, backup.log, update.log
  backups/                        # BACKUP_DIR (default: alongside install)

/etc/systemd/system/minecraft.service   # Systemd unit
/etc/sudoers.d/minecraft                # Service user permissions
```

## Testing

Tests run in a VM to validate the full install/service/backup/update lifecycle.

### Apple Silicon Macs (Lima — recommended)

Uses Apple Virtualization.framework for native arm64 boot (~20s) with Rosetta 2 for transparent x86_64 bedrock_server execution.

```bash
brew install lima
cd tests
make up       # Create and provision VM
make test     # Run 28 tests
make destroy  # Tear down
```

Use `make retest` to re-run tests without rebuilding the VM.

### Intel / Linux / CI (Vagrant)

```bash
cd tests
vagrant up --provider=qemu    # or virtualbox
vagrant ssh -c "sudo /vagrant/tests/run_tests.sh"
vagrant destroy
```

## Releasing

Push a version tag to create a GitHub release with signed artifacts:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## Disclaimer

This project is not affiliated with Mojang or Microsoft. Minecraft is a trademark of Mojang AB. The Bedrock Dedicated Server software is downloaded directly from [minecraft.net](https://www.minecraft.net/en-us/download/server/bedrock) and is subject to the [Minecraft End User License Agreement](https://www.minecraft.net/en-us/eula).

## License

MIT
