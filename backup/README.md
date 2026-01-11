# gitraf S3 Backup

Automated backup system for gitraf repositories to S3-compatible storage with scheduled midnight syncs.

## Features

- Automatic daily backups at midnight
- Compression support (tar.gz archives)
- Configurable retention policy
- Support for AWS S3 and S3-compatible storage (MinIO, Backblaze B2, etc.)
- Concurrent run protection (lock file)
- Detailed logging
- Both cron and systemd timer support

## Quick Setup

```bash
# 1. Configure AWS credentials
aws configure

# 2. Edit the configuration file
cp backup.conf backup.conf.bak
nano backup.conf

# 3. Install the cronjob
sudo ./install-cronjob.sh

# 4. Test the backup
sudo ./s3-backup.sh --dry-run
```

## Configuration

Edit `backup.conf` to customize:

| Option | Description | Default |
|--------|-------------|---------|
| `REPOS_DIR` | Directory containing git repositories | `/var/lib/gitraf/repos` |
| `S3_BUCKET` | S3 bucket name (required) | - |
| `S3_PREFIX` | Folder prefix in bucket | `gitraf-backup` |
| `AWS_PROFILE` | AWS CLI profile to use | `default` |
| `RETENTION_DAYS` | Days to keep old backups | `30` |
| `COMPRESSION` | Create tar.gz archives | `true` |

### S3-Compatible Storage

For non-AWS storage like MinIO or Backblaze B2, set the endpoint:

```bash
# In backup.conf
AWS_ENDPOINT_URL="https://s3.example.com"

# Or configure in AWS CLI
aws configure set endpoint_url https://s3.example.com --profile gitraf
```

## Usage

### Manual Backup

```bash
# Run full backup
sudo ./s3-backup.sh

# Dry run (show what would be backed up)
sudo ./s3-backup.sh --dry-run

# List repositories
sudo ./s3-backup.sh --list
```

### Cronjob Management

```bash
# Install cronjob
sudo ./install-cronjob.sh install

# Check status
sudo ./install-cronjob.sh status

# Uninstall
sudo ./install-cronjob.sh uninstall
```

### Using systemd Timer (Alternative)

```bash
# Remove cron, enable systemd timer
sudo rm /etc/cron.d/gitraf-backup
sudo systemctl enable --now gitraf-backup.timer

# Check timer status
systemctl list-timers gitraf-backup.timer
```

## Backup Schedule

Default: Every day at **midnight (00:00)**

To modify the schedule, edit `/etc/cron.d/gitraf-backup`:

```bash
# Every 6 hours
0 */6 * * * root /path/to/s3-backup.sh

# Every Sunday at 3 AM
0 3 * * 0 root /path/to/s3-backup.sh
```

## Logs

Logs are stored in `/var/log/gitraf-backup/`:

- `backup-YYYYMMDD.log` - Daily backup logs
- `cron.log` - Cron execution logs

```bash
# View recent logs
tail -f /var/log/gitraf-backup/backup-$(date +%Y%m%d).log

# Check for errors
grep ERROR /var/log/gitraf-backup/*.log
```

## Restoring from Backup

```bash
# List available backups
aws s3 ls s3://your-bucket/gitraf-backup/repo-name/

# Download specific backup
aws s3 cp s3://your-bucket/gitraf-backup/repo-name/repo_20240115_000001.tar.gz .

# Extract
tar -xzf repo_20240115_000001.tar.gz
```

## Requirements

- AWS CLI (`sudo apt install awscli`)
- Configured AWS credentials
- tar (for compression)

## Troubleshooting

### Backup not running

1. Check cron is installed: `cat /etc/cron.d/gitraf-backup`
2. Check cron service: `systemctl status cron`
3. Check logs: `tail /var/log/gitraf-backup/cron.log`

### Permission denied

```bash
# Make scripts executable
chmod +x s3-backup.sh install-cronjob.sh
```

### AWS credentials not found

```bash
# Configure credentials for root (cron runs as root)
sudo aws configure
```
