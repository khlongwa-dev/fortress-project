# The Fortress Project

A hardened, automated, and documented Linux server built from scratch as the Phase 1 capstone of a personal 110-day Systems Administration roadmap.

This is not a tutorial follow-along. Every decision was made deliberately, every problem was debugged from first principles, and every configuration has a reason behind it. The goal was not just to build something that works but to understand why it works and what breaks when it does not.

---

## What This Project Covers

### Phase 1 — Server Hardening

A fresh Ubuntu Server 24.04 LTS installation locked down from the ground up. Each hardening decision addresses a specific attack vector.

**SSH Port Change — 22 to 5387**

Changing the SSH port from 22 to 5387 does not solve the problem of unauthorised access — it creates friction. An attacker targeting a server will typically begin by scanning port 22. Moving SSH off the default port means they have to perform broader port scanning before they even find the door. That takes time, generates noise in the logs, and if monitoring and alerting are in place, gives an opportunity to detect and respond before anything escalates. It is not a security measure on its own — it is a delay mechanism that works alongside real security measures.

**Disabling Root Login**

Root is the superuser. An attacker who gains root access has complete control over the server — they can read any file, modify any configuration, install anything, and cover their tracks. Disabling root login over SSH means that even if an attacker obtains a valid password, they cannot log in as root directly. They would first need to compromise a regular user account and then escalate privileges separately. That is an additional barrier that reduces the blast radius of a compromised credential.

**Disabling Password Authentication**

Passwords are vulnerable to brute force attacks. Given enough attempts, a determined attacker will eventually find the right combination, especially against weak or reused passwords. SSH key pair authentication eliminates this entirely. To authenticate, a user must possess the private key — a cryptographic file that never travels over the network. The server holds only the public key. Without the private key, authentication is impossible regardless of how many attempts are made. A brute force attack against key-based authentication has no meaningful attack surface.

**Restricting SSH Access by IP via UFW**

Fail2ban bans an IP after failed attempts. But that means attempts still reach the server first. UFW operates at a layer below that — it drops traffic before it even gets to the SSH daemon. By restricting SSH to only the host machine IP (192.168.56.1), every other machine on the network is blocked at the firewall before any authentication attempt can be made. No other machine can even knock on the door. This is the principle of whitelisting: define exactly what is allowed, deny everything else. The server does not receive traffic from anywhere — it receives traffic from trusted sources only.

**fail2ban with Permanent Bans**

fail2ban monitors authentication logs and bans IPs that exceed the failed attempt threshold. The ban time was set to -1, which means permanent. A temporary ban of 10 minutes means an attacker can resume after waiting. A brute force attack that is banned permanently after two attempts is stopped completely. The ban must be lifted manually, which means any banned IP requires a deliberate human decision to restore access. This is intentional. In a production environment with proper monitoring, a permanently banned IP is a record of a blocked intrusion attempt — worth reviewing, not automatically forgetting.

The sshd jail was specifically enabled because SSH is the primary access point. If anything on this server is going to be attacked, it is SSH. Watching it closely is not optional.

**50-cloud-init.conf Override Identified and Neutralised**

A file in /etc/ssh/sshd_config.d/ was silently overriding every hardening setting after each SSH restart. PasswordAuthentication was being re-enabled. PermitRootLogin was being ignored. The hardening was being undone by a cloud-init remnant that had no business existing on a manually configured server. Truncating that file was necessary to make the hardening stick.

### Phase 2 — Automation

Nothing is done manually twice.

The motivation for this phase was personal experience. During this project the server was broken and had to be rebuilt from scratch. Important notes, configuration files, and work that had not been backed up were lost. Rebuilding took time and was avoidable. A human forgets to back up. A scheduled job does not.

The automation pipeline works as follows: files on the Ubuntu Server sync to the host machine every minute via rsync over SSH. Every 30 minutes the host commits and pushes any changes to GitHub. On shutdown, a systemd service fires a final push to ensure nothing is lost in the gap between the last cron run and the machine powering off.

The pipeline is designed around separation of concerns. The server owns its files and makes them available. The host is responsible for backup and version control. GitHub holds the permanent offsite record. No machine tries to do another machine's job.

- Real-time file sync from Ubuntu Server to host machine using rsync over SSH, triggered every minute via cron
- Automated git commits and pushes to GitHub every 30 minutes, with intelligent detection of untracked, modified, and staged changes using git status --porcelain
- Systemd shutdown service that fires a final sync and push before the machine powers off
- All automation runs without SSH agent dependency, using explicit key references for reliable execution in cron's minimal environment

### Phase 3 — Networking

No mysteries. Every packet has a story.

- Network interfaces documented and understood at the layer level
- Hostname resolution configured via /etc/hosts for lab machines
- Network intentionally broken and recovered: default route removal, interface shutdown, DNS corruption
- Traffic captured and analysed with tcpdump: ICMP, TCP three-way handshake, SSH encrypted sessions, DNS queries and responses
- Traceroute used to map the path from Durban to Google across 15 hops, observing SA infrastructure before the international handoff
- Windows Firewall behaviour observed through packet analysis — understanding that 100% packet loss does not always mean a network failure

---

## Lab Environment

| Machine | Role | IP Address | OS |
|---|---|---|---|
| Host Machine | Daily driver, backup destination | 192.168.56.1 | Ubuntu 25.10 |
| Ubuntu Server | Primary lab server | 192.168.56.104 | Ubuntu Server 24.04 LTS |
| Windows Server | AD and infrastructure learning | 192.168.56.102 | Windows Server 2022 Evaluation |

**Network:** VirtualBox Host-Only Adapter (vboxnet0) — 192.168.56.0/24

Both VMs also have a NAT adapter for internet access.

---

## Repository Structure

```
fortress-project/
├── configs
|   └── 50-cloud-init.yaml
├── phase1-hardening
│   ├── fail2ban
│   │   └── jail.local
│   ├── services
│   │   └── final-push.service
│   ├── ssh
│   │   └── sshd_config
│   └── ufw
│       └── ufw-rules.txt
├── phase2-automation
│   ├── gitpush.sh
│   └── sync-script.sh
├── phase3-networking
│   ├── hosts-config.txt
│   └── networking-topology.md
├── README.md
└── RUNBOOK.md

```

---

## Key Problems Solved

**fail2ban not banning after failed SSH attempts**

Fail2ban was correctly configured but consistently counted one failure instead of three. The root cause was rsyslog's `$RepeatedMsgReduction on` setting, which compressed identical consecutive log entries into a single line with a "message repeated N times" suffix. Fail2ban's regex could not parse that format and therefore only counted the first entry. Setting `$RepeatedMsgReduction off` in rsyslog.conf resolved the issue. The ban fired correctly on the second failed attempt after the fix.

**50-cloud-init.conf silently overriding sshd_config**

PasswordAuthentication and PermitRootLogin settings in sshd_config were being ignored after SSH restarts. The cause was a file in /etc/ssh/sshd_config.d/ that is loaded after the main config and takes precedence. Truncating that file and restarting SSH resolved the override.

**rsync deleting .git directory on host**

The --delete flag in rsync was removing the .git folder from the host destination on every sync, wiping git history and breaking the push pipeline. Adding --exclude='.git' to the rsync command resolved this.

**gitpush script not detecting new untracked files**

The original change detection used git diff which only sees tracked files. Newly synced files that had never been added to git were invisible to this check. Replacing the condition with git status --porcelain fixed the detection, as it reports untracked, modified, and staged changes.

**cron not authenticating over SSH**

Scripts ran correctly when executed manually but failed silently under cron. The cause was cron's minimal environment having no SSH agent loaded. Specifying the private key explicitly with -i /path/to/key in both the rsync and GIT_SSH_COMMAND resolved the authentication without requiring an agent.

---

## What I Learned

The most valuable lessons from this project were not in the configurations. They were in the debugging.

Every major problem in this project was caused by something in a layer below the tool I was working with. fail2ban was not broken — rsyslog was hiding information from it. SSH hardening was not broken — a cloud-init override was quietly undoing it. The diagnosis pattern that emerged from these problems is the same every time: when a tool behaves unexpectedly, check what that tool is seeing before changing the tool itself.

Networking made abstract concepts visible. Watching a DNS query leave the machine and an answer come back, seeing the TCP handshake in a packet capture, tracing a packet from Durban to Google across 15 hops — these things move networking from theory to something you have actually observed.

The automation pipeline taught a lesson about separation of concerns. The server owns its files. The host owns the backup. GitHub owns the history. Each machine has one responsibility and does not try to do the other's job.

Security is not one thing. It is layers. The port change buys time. The firewall controls who can knock. Key authentication controls who can enter. fail2ban stops those who try anyway. No single measure is enough on its own — the value is in the combination.

---

## Part of a Larger Journey

This project is Phase 1 of a personal 110-day Systems Administration roadmap. The full roadmap covers Linux administration, Windows Server and Active Directory, networking and security, servers and services, and cloud infrastructure with Docker and automation.

Every phase is documented publicly as it is completed.
