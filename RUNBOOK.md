# Runbook — The Fortress Project

This document covers how to operate, maintain, and recover the Fortress Project lab environment. It is written for someone who understands Linux basics but has not worked with this specific setup before. Every procedure includes the reason behind it, not just the steps.

---

## System Overview

Two virtual machines running on a single host under VirtualBox, connected via a Host-Only private network. The Ubuntu Server is the primary working environment. The Windows Server exists for Active Directory and Windows infrastructure learning in Phase 2.

The host machine handles backups. The Ubuntu Server handles its own files. GitHub holds the permanent record of everything.

---

## Access Information

### SSH into Ubuntu Server

```bash
ssh -p 5387 khlongwa@192.168.56.104
```

Or if the SSH config alias is set up on the host:

```bash
ssh ubuntu-server
```

SSH is on port 5387. Port 22 is not listening. Password authentication is disabled. Key-based authentication only. The authorised key must be present in `/home/khlongwa/.ssh/authorized_keys` on the server.

### Windows Server

Access via VirtualBox GUI directly. RDP can be configured if needed but is not set up in this environment.

### VirtualBox VM Management

Start VMs headless from host terminal:

```bash
VBoxManage startvm "Ubuntu-Server" --type headless
VBoxManage startvm "Windows-Server" --type headless
```

Stop VMs gracefully:

```bash
ubuntu-shutdown
```

Force power off if unresponsive:

```bash
VBoxManage controlvm "Ubuntu-Server" poweroff
```

---

## Network Reference

| Host | IP Address | Role |
|---|---|---|
| Host machine | 192.168.56.1 | Backup destination, daily driver |
| Ubuntu Server | 192.168.56.104 | Primary lab server |
| Windows Server | 192.168.56.102 | AD and Windows infrastructure |

**Network:** 192.168.56.0/24 — VirtualBox Host-Only

Each VM has two network adapters:
- Adapter 1: NAT — internet access
- Adapter 2: Host-Only — communication between VMs and host

### Verify network connectivity

```bash
# From Ubuntu Server
ping -c 4 192.168.56.1    # host machine
ping -c 4 192.168.56.102  # windows server
ping -c 4 8.8.8.8         # internet

# Check interfaces
ip addr show
ip route show
```

---

## Services Running on Ubuntu Server

| Service | Port | Purpose |
|---|---|---|
| SSH (sshd) | 5387 | Remote access |
| fail2ban | — | Intrusion prevention |
| UFW | — | Firewall |
| cron | — | Scheduled automation |
| final-push.service | — | Shutdown git push |

Check all service statuses:

```bash
sudo systemctl status ssh
sudo systemctl status fail2ban
sudo ufw status
sudo systemctl status final-push.service
```

---

## Firewall Rules

UFW is configured with default deny incoming, default allow outgoing.

```bash
sudo ufw status verbose
```

Current allowed inbound traffic:

| Port | From | Reason |
|---|---|---|
| 5387 | 192.168.56.1 | SSH from host machine only |

To add a new rule:

```bash
sudo ufw allow from [IP] to any port [PORT]
sudo ufw reload
```

To remove a rule:

```bash
sudo ufw delete allow from [IP] to any port [PORT]
```

---

## fail2ban Operations

### Check current ban status

```bash
sudo fail2ban-client status sshd
```

This shows currently banned IPs, total failed attempts, and which log file is being monitored.

### Unban an IP address

```bash
sudo fail2ban-client set sshd unbanip [IP_ADDRESS]
```

This is the procedure if you lock yourself out during testing. Access the server via the VirtualBox console first, then run the unban command.

### Check fail2ban logs

```bash
sudo tail -50 /var/log/fail2ban.log
```

### Important configuration note

fail2ban requires `$RepeatedMsgReduction off` in `/etc/rsyslog.conf`. Without this setting, rsyslog compresses repeated log entries and fail2ban undercounts failed attempts. If fail2ban stops banning correctly after a system update, check this setting first.

Current jail configuration lives in `/etc/fail2ban/jail.local`. Never edit `jail.conf` directly — it gets overwritten on updates.

### Restart fail2ban after config changes

```bash
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

---

## SSH Hardening Reference

Configuration file: `/etc/ssh/sshd_config`

Key settings:

```
Port 5387
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
LogLevel VERBOSE
```

**Important:** There is a file at `/etc/ssh/sshd_config.d/50-cloud-init.conf` that was truncated to prevent it from overriding the above settings. If SSH hardening appears to stop working after an update, check whether this file has been regenerated with conflicting settings.

After any change to sshd_config:

```bash
sudo sshd -t                    # test config for syntax errors
sudo systemctl restart ssh      # apply changes
sudo systemctl status ssh       # confirm running
```

Always test that your existing SSH session still works before closing it. Never close your only session until you have confirmed a new one connects.

---

## Automation Pipeline

### How it works

```
Ubuntu Server files change
        |
        v
cron on host runs sync-script.sh every minute
        |
        v
rsync pulls changed files from server to host
        |
        v
cron on host runs gitpush.sh every 30 minutes
        |
        v
git commits and pushes to GitHub
        |
        v
On server shutdown: final-push.service fires gitpush.sh one last time
```

### Script locations on host machine

```
/home/khlongwa/scripts/sync-script.sh
/home/khlongwa/scripts/gitpush.sh
```

### Log locations

```
/home/khlongwa/logs/sync.log
/home/khlongwa/logs/gitpush.log
```

### Check cron jobs

```bash
crontab -l
```

Expected output:

```
* * * * * /home/khlongwa/scripts/sync-script.sh
*/30 * * * * /home/khlongwa/scripts/gitpush.sh
```

### Verify cron is running scripts

```bash
grep CRON /var/log/syslog | tail -20
```

### Run scripts manually

```bash
bash /home/khlongwa/scripts/sync-script.sh
bash /home/khlongwa/scripts/gitpush.sh
```

### Shutdown service

The final-push.service is a systemd unit that runs gitpush.sh before the machine powers off. It ensures any files synced in the last 30 minutes are not lost between cron intervals.

Check status:

```bash
sudo systemctl status final-push.service
```

Test manually:

```bash
sudo systemctl start final-push.service
```

If the service is not enabled:

```bash
sudo systemctl enable final-push.service
```

---

## Adding a New User

```bash
# Create user with home directory
sudo adduser username

# Add to sudo group if admin access needed
sudo usermod -aG sudo username

# Verify
id username
cat /etc/passwd | grep username
```

To create a restricted user with no login ability:

```bash
sudo useradd -s /usr/sbin/nologin -m username
```

---

## Common Troubleshooting

### Cannot SSH into server

Work through these in order:

1. Is the VM running?
```bash
VBoxManage list runningvms
```

2. Is the network interface up on the server? Access via VirtualBox console:
```bash
ip addr show enp0s8
```

3. Is SSH listening on port 5387?
```bash
sudo ss -tulnp | grep 5387
```

4. Is UFW blocking the connection?
```bash
sudo ufw status
```

5. Is your IP banned by fail2ban?
```bash
sudo fail2ban-client status sshd
```

If banned, unban from VirtualBox console:
```bash
sudo fail2ban-client set sshd unbanip 192.168.56.1
```

### Files not syncing to host

1. Check cron is running:
```bash
grep CRON /var/log/syslog | tail -10
```

2. Run sync script manually and check output:
```bash
bash /home/khlongwa/scripts/sync-script.sh
```

3. Check sync log:
```bash
cat /home/khlongwa/logs/sync.log
```

4. Verify SSH key works without agent:
```bash
ssh -p 5387 -i /home/khlongwa/.ssh/id_ed25519 khlongwa@192.168.56.104 "echo connected"
```

### Files not pushing to GitHub

1. Run gitpush script manually:
```bash
bash /home/khlongwa/scripts/gitpush.sh
```

2. Check if there are changes to push:
```bash
cd /home/khlongwa/Documents/sysadmin-lab
git status --porcelain
```

3. Test GitHub SSH authentication:
```bash
ssh -T git@github.com
```

Expected response: `Hi khlongwa-dev! You've successfully authenticated`

4. Check git remote is correct:
```bash
git remote -v
```

### Server not reachable from host

1. Ping the server:
```bash
ping -c 4 192.168.56.104
```

2. If ping fails, check the Host-Only interface on the server via VirtualBox console:
```bash
ip addr show enp0s8
sudo netplan apply
```

3. Check VirtualBox Host-Only network still exists:
```bash
VBoxManage list hostonlyifs
```

---

## Recovery Procedures

### Rebuild Ubuntu Server from scratch

This happened once during this project and took less than two hours the second time. The process is faster when you know what you are doing.

1. Download Ubuntu Server 24.04 LTS ISO
2. Create new VM in VirtualBox — 2GB RAM, 2 cores, 30GB storage
3. Install with OpenSSH server selected
4. Configure dual network adapters — NAT and Host-Only
5. Run netplan configuration for enp0s8
6. Clone the sysadmin-lab repo from GitHub — all configs are there
7. Reapply hardening configs from phase1-hardening/
8. Reinstall fail2ban and restore jail.local
9. Set $RepeatedMsgReduction off in rsyslog.conf
10. Re-enable final-push.service
11. Test SSH connection from host
12. Restore cron jobs on host machine

Everything needed to rebuild is in this repository. That is the point of having it.

### Restore a specific file from GitHub

```bash
cd /home/khlongwa/Documents/sysadmin-lab
git log --oneline           # find the commit you want
git checkout [commit] -- path/to/file
```

---

## Security Notes

- SSH is restricted to connections from 192.168.56.1 only via UFW. Any other IP attempting SSH will be blocked at the firewall before fail2ban even sees it.
- fail2ban bans are permanent (bantime = -1). If a legitimate IP gets banned it must be manually unbanned via the VirtualBox console or a secondary access method.
- The 50-cloud-init.conf file has been truncated. If Ubuntu updates regenerate this file with conflicting SSH settings, hardening will silently break. Check this file if SSH settings appear to stop working after a system update.
- Private keys are never committed to this repository. Config files use placeholders where sensitive values appear.
- sudo NOPASSWD is set only for /sbin/shutdown and /sbin/reboot to support the remote shutdown alias. It is not set globally.
