# server-updates

A small, safe updater script with scheduling examples for automated system updates.

<div align="left">

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![Repo Status][repo-shield]][repo-url]

</div>

## What this repo provides

- `update-server.sh` — a small, safe updater script with modes: `update-only`, `security`, `full`
- `etc/sample.conf` — sample config you can copy to `/etc/server-updates.conf`
- `systemd/server-updates.service` and `systemd/server-updates.timer` — example systemd unit/timer to run weekly

## Recommendations

**How often to schedule:**
- **Security updates:** Run daily (or rely on `unattended-upgrades`). Security patches should be applied quickly; a daily check is a good balance.
- **Full upgrades:** Run weekly (e.g., Sunday 03:00). Full upgrades may update kernels and packages which can require reboots.

**Suggested defaults:**
- Use `--mode security` daily, and `--mode full` weekly.

## Installation

### Quick Install

Use the provided installer to place files and optionally enable the timer:

```bash
sudo bash install.sh --enable-timer
```

### Manual Install

If you prefer manual steps:

```bash
sudo cp systemd/server-updates.service /etc/systemd/system/
sudo cp systemd/server-updates.timer /etc/systemd/system/
sudo cp update-server.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/update-server.sh
```

Then reload systemd and enable the timer:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now server-updates.timer
```

## Scheduling Examples

### Cron

Add the following to root's crontab (`sudo crontab -e`):

```bash
# Daily security-only updates
0 3 * * * /usr/local/bin/update-server.sh --mode security >> /var/log/server-updates.log 2>&1

# Weekly full upgrade (Sunday 03:30)
30 3 * * 0 /usr/local/bin/update-server.sh --mode full >> /var/log/server-updates.log 2>&1
```

### Systemd Timer

The included systemd timer provides automatic weekly updates. Enable it with:

```bash
sudo systemctl enable --now server-updates.timer
```

Check timer status:

```bash
sudo systemctl status server-updates.timer
sudo systemctl list-timers
```

## Configuration

Copy `etc/sample.conf` to `/etc/server-updates.conf` and adjust defaults (MODE, LOG, DRY_RUN):

```bash
sudo cp etc/sample.conf /etc/server-updates.conf
sudo nano /etc/server-updates.conf
```

The script will automatically load `/etc/server-updates.conf` on startup.

## Slack Notifications

To enable Slack notifications:

1. Create `/etc/server-updates.conf` (copy `etc/sample.conf`)
2. Set `SLACK_WEBHOOK_URL` to an Incoming Webhook URL from Slack

The script will send three types of messages:
- **Start:** When the run begins
- **Failure:** When a step fails (one message per failed step)
- **Completed:** When the run finishes (summary of successes/failures)

**Security note:** Treat your webhook URL like a secret. Do not commit it to git. Prefer storing it in a secure location (Vault, encrypted file) and reference it in `/etc/server-updates.conf`.

### Message Format

Messages use Slack attachments and include:
- Host, mode, details, and a link/path to the verbose log
- Color coding: blue for start, red for failure, green/orange for completion
- Optional `SLACK_CHANNEL` in `/etc/server-updates.conf` to override the destination channel

**Examples:**
- Start: "Starting system update on corebreeze — mode=full — 2025-10-24T23:00:00Z"
- Failure: "FAILURE on corebreeze: Upgrade installed packages (exit 1) — 2025-10-24T23:01:00Z"
- Completion: "COMPLETED on corebreeze: 5/6 steps succeeded — 2025-10-24T23:05:00Z"

## Notes and Safety

- The script uses a lock (in `/var/lock`) to avoid concurrent runs
- The `security` mode prefers `unattended-upgrade` if installed; install and configure `unattended-upgrades` for production security patching
- For non-interactive upgrades we set `DEBIAN_FRONTEND=noninteractive`. Test on a staging host first
- Consider enabling automatic reboot on kernel upgrades only after testing, and ensure you have monitoring and a maintenance window

## Next Steps

1. Install `unattended-upgrades` and configure `/etc/apt/apt.conf.d/50unattended-upgrades` if you want automatic security patches
2. Add log rotation for `/var/log/server-updates.log` (e.g., via `/etc/logrotate.d/server-updates`)
3. Test the script in `--dry-run` mode on a staging server

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

See the LICENSE file for details.

---

[contributors-shield]: https://img.shields.io/github/contributors/ashraftown/server-updates.svg
[contributors-url]: https://github.com/ashraftown/server-updates/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/ashraftown/server-updates.svg
[forks-url]: https://github.com/ashraftown/server-updates/network/members
[stars-shield]: https://img.shields.io/github/stars/ashraftown/server-updates.svg
[stars-url]: https://github.com/ashraftown/server-updates/stargazers
[issues-shield]: https://img.shields.io/github/issues/ashraftown/server-updates.svg
[issues-url]: https://github.com/ashraftown/server-updates/issues
[repo-shield]: https://img.shields.io/badge/repo-active-brightgreen.svg
[repo-url]: https://github.com/ashraftown/server-updates