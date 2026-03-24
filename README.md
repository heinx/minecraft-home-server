# Minecraft Home Server

Easy-to-install Minecraft Bedrock Dedicated Server for home Linux (Ubuntu) servers. Runs reliably with automatic updates, backups, and monitoring.

## Quick Install

```bash
curl -sL https://github.com/heinx/minecraft-home-server/releases/latest/download/minecraft-home-server.tar.gz | tar xz
cd minecraft-home-server
sudo ./install.sh
```

The installer prompts for server name, world name, ports, etc. For non-interactive installs, provide a config file:

```bash
sudo ./install.sh --config /path/to/config.env
```

### Verify the download (optional)

```bash
gh attestation verify minecraft-home-server.tar.gz --repo heinx/minecraft-home-server
```

## What it does

- Runs Bedrock Dedicated Server as a systemd service (auto-start on boot, auto-restart on crash)
- Nightly world backups with configurable retention (default: 20)
- Optional offsite backup to Google Drive (or any rclone remote)
- Automatic server updates from Microsoft's download API
- Email notifications on failures (update, backup, or server crash)

## Import an existing world

Set these in your `config.env` before installing:

```bash
IMPORT_WORLD="/path/to/your/world"           # directory or .zip
IMPORT_SERVER_PROPERTIES="/path/to/server.properties"  # optional
```

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
| `OFFSITE_BACKUP_ENABLED` | `false` | Enable rclone offsite sync |
| `OFFSITE_BACKUP_REMOTE` | | rclone remote path (e.g., `gdrive:minecraft-backups`) |
| `NOTIFY_ENABLED` | `false` | Enable email notifications |
| `NOTIFY_EMAIL` | | Email address for notifications |

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

Tests run in a Vagrant VM to safely validate the full install/service/backup/update lifecycle:

```bash
cd tests
vagrant up        # Provisions Ubuntu 22.04 VM and installs dependencies
vagrant ssh -c "sudo /vagrant/tests/run_tests.sh"
vagrant destroy   # Tear down
```

## Releasing

Push a version tag to create a GitHub release with signed artifacts:

```bash
git tag v1.0.0
git push origin v1.0.0
```

## License

MIT
