# server-updates — small updater + scheduling examples

<div align="left">

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![License][license-shield]][license-url]

</div>

What this repo provides
- `update-server.sh` — a small, safe updater script with modes: `update-only`, `security`, `full`.
- `etc/sample.conf` — sample config you can copy to `/etc/server-updates.conf`.
- `systemd/server-updates.service` and `systemd/server-updates.timer` — example systemd unit/timer to run weekly.

Recommendations (how often to schedule)
- Security updates: run daily (or rely on `unattended-upgrades`). Security patches should be applied quickly; a daily check is a good balance.
- Full upgrades: run weekly (e.g., Sunday 03:00). Full upgrades may update kernels and packages which can require reboots.

Suggested defaults
- Use `--mode security` daily, and `--mode full` weekly.

Cron example
Add the following to root's crontab (`sudo crontab -e`):

```
# daily security-only (if you prefer cron)
0 3 * * * /usr/local/bin/update-server.sh --mode security >> /var/log/server-updates.log 2>&1

# weekly full upgrade (Sunday 03:30)
30 3 * * 0 /usr/local/bin/update-server.sh --mode full >> /var/log/server-updates.log 2>&1
```

Systemd timer example
1. Copy files:

```
Use the provided installer to place files and optionally enable the timer:

```
sudo bash install.sh --enable-timer
```

If you prefer manual steps:

```
sudo cp systemd/server-updates.service /etc/systemd/system/
sudo cp systemd/server-updates.timer /etc/systemd/system/
sudo cp update-server.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/update-server.sh
```
```

2. Reload systemd and enable timer:

```
sudo systemctl daemon-reload
sudo systemctl enable --now server-updates.timer
```

Notes and safety
- The script uses a lock (in `/var/lock`) to avoid concurrent runs.
- The `security` mode prefers `unattended-upgrade` if installed; install and configure `unattended-upgrades` for production security patching.
- For non-interactive upgrades we set `DEBIAN_FRONTEND=noninteractive`. Test on a staging host first.
- Consider enabling automatic reboot on kernel upgrades only after testing, and ensure you have monitoring and a maintenance window.

Configuration
- Copy `etc/sample.conf` to `/etc/server-updates.conf` and adjust defaults (MODE, LOG, DRY_RUN). The script will load `/etc/server-updates.conf` on startup.

Install notes
- The `install.sh` script copies the updater to `/usr/local/bin`, installs systemd units and the sample logrotate config (if present), reloads systemd, and can enable the timer with `--enable-timer`.

Slack notifications
- To enable Slack notifications create `/etc/server-updates.conf` (copy `etc/sample.conf`) and set `SLACK_WEBHOOK_URL` to an Incoming Webhook URL from Slack. The script will send three messages:
	- Start: when the run begins
	- Failure: when a step fails (one message per failed step)
	- Completed: when the run finishes (summary of successes/failures)

Security note: treat your webhook URL like a secret. Do not commit it to git. Prefer storing it in a secure location (Vault, encrypted file) and reference it in `/etc/server-updates.conf`.

Message format
- Messages now use Slack attachments and include:
	- host, mode, details, and a link/path to the verbose log
	- color coding: blue for start, red for failure, green/orange for completion
	- optional `SLACK_CHANNEL` in `/etc/server-updates.conf` to override the destination channel

Examples
- Start: "Starting system update on corebreeze — mode=full — 2025-10-24T23:00:00Z"
- Failure: "FAILURE on corebreeze: Upgrade installed packages (exit 1) — 2025-10-24T23:01:00Z"
- Completion: "COMPLETED on corebreeze: 5/6 steps succeeded — 2025-10-24T23:05:00Z"

If you want richer Slack blocks or links to a centralized log viewer, tell me which fields you'd like and I can extend the payload format.

Next steps (suggested)
1. Install `unattended-upgrades` and configure `/etc/apt/apt.conf.d/50unattended-upgrades` if you want automatic security patches.
2. Add log rotation for `/var/log/server-updates.log` (e.g., via `/etc/logrotate.d/server-updates`).
3. Test the script in `--dry-run` mode on a staging server.
