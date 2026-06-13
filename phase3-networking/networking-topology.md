# Phase 3 — Networking

## Overview

The goal of this phase was not to memorise networking commands. The goal was to understand what is actually happening when two machines communicate — and then make that visible with real tools on a real network.

Every concept in this phase was observed, not just read about. Packets were captured. Routes were removed and restored. DNS was broken and diagnosed. A traceroute was followed from Durban to Google across 15 hops. The network has no mysteries after this phase.

---

## Network Topology

```
                    +------------------+
                    |   Host Machine   |
                    |  192.168.56.1    |
                    |   Ubuntu 25.10   |
                    +--------+---------+
                             |
                    vboxnet0 | 192.168.56.0/24
                    Host-Only Network
                    /                  \
         +---------+----------+    +---+------------------+
         |   Ubuntu Server    |    |   Windows Server     |
         |   192.168.56.104   |    |   192.168.56.102     |
         | Ubuntu Server LTS  |    | Windows Server 2022  |
         +--------------------+    +----------------------+
```

Each VM has two network adapters:

| Adapter | Type | Purpose |
|---|---|---|
| enp0s3 | NAT | Internet access via host |
| enp0s8 | Host-Only | Communication between VMs and host |

The Host-Only network is entirely private. Nothing on this network is reachable from the internet. The NAT adapter provides outbound internet access through VirtualBox's virtual router.

---

## Network Interface Reference

### Ubuntu Server

```bash
ip addr show
```

**enp0s3 — NAT adapter**
- IP: 10.0.2.15
- Gateway: 10.0.2.2 (VirtualBox NAT router)
- Purpose: Internet access

**enp0s8 — Host-Only adapter**
- IP: 192.168.56.104
- Purpose: Communication with host and Windows Server
- Configured via: /etc/netplan/

**Why enp0s8 needed manual configuration**

After installing Ubuntu Server, only enp0s3 was configured in the netplan file. enp0s8 was present but had no IP address assigned and its state showed as DOWN. The two machines could not communicate until the netplan configuration was updated to include enp0s8 with DHCP enabled and `netplan apply` was run. This was the first real networking problem of the project — the interface existed but the OS did not know what to do with it until told.

### Routing Table

```bash
ip route show
```

```
default via 10.0.2.2 dev enp0s3
192.168.56.0/24 dev enp0s8 proto kernel scope link src 192.168.56.104
10.0.2.0/24 dev enp0s3 proto kernel scope link src 10.0.2.15
```

Reading this table:

- For traffic destined for **192.168.56.0/24** — send it directly out enp0s8. No router needed. The destination is on the same network.
- For **everything else** — send it to 10.0.2.2 (the default gateway). Let the NAT router handle it.

The routing table answers one question: which door does this packet leave through?

---

## Hostname Resolution

Rather than referencing machines by IP address, /etc/hosts was configured to allow communication by name.

```bash
cat /etc/hosts
```

Entries added:

```
192.168.56.1    host-machine
192.168.56.102  windows-server
192.168.56.104  ubuntu-server
```

This file is consulted before DNS. When `ping windows-server` is run, the OS checks /etc/hosts first, finds the mapping, and resolves the name without making a DNS query. It is the simplest form of name resolution — a local lookup table.

This is also how DNS works at its core, just distributed across servers worldwide instead of a local file.

---

## ARP — How IP Addresses Become MAC Addresses

IP addresses tell a packet where to go. MAC addresses tell the network hardware who to actually deliver it to. These are two different identities and the translation between them is handled by ARP — Address Resolution Protocol.

When a machine wants to send a packet to 192.168.56.102 it knows the IP but not the MAC address. It broadcasts a question to the entire network: who has 192.168.56.102? The machine with that IP responds with its MAC address. The result is cached in the ARP table — the neighbor table.

### Observing ARP in action

```bash
# Clear the ARP cache
sudo ip neigh flush all

# Ping the Windows Server to trigger an ARP request
ping -c 1 192.168.56.102

# Inspect the neighbor table immediately after
ip neigh
```

After the ping, the Windows Server's MAC address appears in the table. The machine asked a question, got an answer, and remembered it. That is ARP.

---

## Traffic Analysis with tcpdump

tcpdump captures packets at the network interface level. It makes the invisible visible — actual traffic flowing across the network, readable in real time.

### Capturing ICMP — ping traffic

```bash
sudo tcpdump -i enp0s8 -n icmp
```

A single line from the capture:

```
15:15:18.602188 IP 192.168.56.104 > 192.168.56.102: ICMP echo request, id 3867, seq 2, length 64
```

Reading this:

| Field | Value | Meaning |
|---|---|---|
| Timestamp | 15:15:18.602188 | When the packet was captured |
| Protocol | IP | Network layer |
| Source | 192.168.56.104 | Ubuntu Server — origin of the packet |
| Direction | > | Travelling toward destination |
| Destination | 192.168.56.102 | Windows Server |
| Type | ICMP echo request | A ping going out |
| seq | 2 | Second packet in the sequence |
| length | 64 | Size of the packet in bytes |

Four pings produce eight lines — four requests going out, four replies coming back. Request and reply. Two machines having a conversation at the packet level.

**What was observed:** Windows Server was initially showing 100% packet loss and not appearing in the capture output at all. The network was working correctly — Windows Firewall was blocking inbound ICMP. Enabling an inbound ICMPv4 rule on Windows resolved it. The distinction between network unreachable and host blocking is important: network unreachable fails immediately, host blocking means packets arrive but are deliberately dropped at the destination.

### Capturing SSH traffic

```bash
sudo tcpdump -i enp0s8 -n port 5387 -c 20 -w /tmp/ssh-capture.pcap
sudo tcpdump -r /tmp/ssh-capture.pcap
```

What the capture revealed:

**The TCP three-way handshake** — every TCP connection begins with this exchange before any data moves:

```
Client → Server:  SYN      "Can we talk?"
Server → Client:  SYN-ACK  "Yes. Can you hear me?"
Client → Server:  ACK      "Yes."
```

**The ongoing session** — after the handshake:

```
[P.]   Data being pushed — a command typed, a response sent
[.]    Acknowledgement — confirming the data arrived
```

The rhythm of an SSH session is visible in the packet capture. What is not visible is the content. Every payload is encrypted. An observer on the network can see that two machines are communicating and how frequently — but not what they are saying. That is what SSH encryption provides.

### Capturing DNS queries

```bash
sudo tcpdump -i enp0s3 -n port 53 -c 10
```

Running `nslookup google.com` while this capture was active produced the following exchange:

```
Query:   A? google.com
Answer:  142.251.47.46
```

- **Port 53** — DNS always uses port 53, worldwide
- **A?** — a query for an A record, meaning "I have a name, give me an IPv4 address"
- **142.251.47.46** — Google's IP, the answer

The query goes to the nameserver listed in /etc/resolv.conf, which on Ubuntu is managed by systemd-resolved. The response comes back in milliseconds.

DNS record types observed and understood during this phase:

| Record | Purpose |
|---|---|
| A | Name to IPv4 address |
| AAAA | Name to IPv6 address |
| MX | Mail server for a domain |
| CNAME | Name to another name (alias) |
| PTR | IP to name (reverse lookup) |

---

## Network Break and Fix Log

Each break was performed intentionally, one at a time. Before fixing anything the symptom was observed and the affected layer was identified.

---

### Break 1 — Default Route Removed

**Command:**
```bash
sudo ip route del default
```

**Observed symptom:**
```bash
ping 8.8.8.8       # failed — destination host unreachable
ping 192.168.56.102 # succeeded — Windows Server still reachable
```

**Layer affected:** Network layer — routing

**Diagnosis:** The default route is the gateway of last resort. Without it, the machine does not know where to send traffic that is not on a directly connected network. Traffic destined for 192.168.56.0/24 has a specific route and still works. Traffic destined for anything outside the local network has nowhere to go.

**Fix:**
```bash
sudo ip route add default via 10.0.2.2
```

**What this teaches:** Connectivity problems are layer-specific. The network interface was up, the local network was reachable, but external connectivity was gone. Knowing which layer is affected tells you exactly where to look.

---

### Break 2 — Host-Only Interface Brought Down

**Command:**
```bash
sudo ip link set enp0s8 down
```

**Observed symptom:**
```bash
ping 192.168.56.102  # failed — Windows Server unreachable
ping 8.8.8.8         # succeeded — internet still reachable via enp0s3
ssh ubuntu-server    # failed from host — connection refused
```

**Layer affected:** Data link layer — the interface itself

**Diagnosis:** enp0s8 is the only path between the Ubuntu Server and the rest of the lab network. Bringing it down isolates the server from the host and Windows Server entirely. enp0s3 (NAT) is unaffected and internet access continues through it.

**Fix:**
```bash
sudo ip link set enp0s8 up
```

**What this teaches:** A machine can have partial connectivity. Internet works, local network does not. Or vice versa. Each interface and each route is independent. Diagnosing connectivity requires knowing which path is broken, not just whether the machine is online.

---

### Break 3 — DNS Corrupted

**Command:**
```bash
echo "nameserver 1.2.3.4" | sudo tee /etc/resolv.conf
```

**Observed symptom:**
```bash
ping google.com  # failed — Name or service not known
ping 8.8.8.8     # succeeded — direct IP still reachable
```

**Layer affected:** Application layer — DNS resolution

**Diagnosis:** The network itself was completely functional. The routing table was intact. The interfaces were up. The failure was entirely in name resolution. The machine could not translate google.com to an IP address because it was sending DNS queries to 1.2.3.4 — an address that does not respond.

The distinction between these two results is the diagnostic: if an IP address works but a hostname does not, DNS is the problem. Not the network.

**What was discovered during this break:**

/etc/resolv.conf on Ubuntu is not a regular file. It is a symlink:

```bash
ls -la /etc/resolv.conf
# /etc/resolv.conf -> ../run/systemd/resolve/stub-resolv.conf
```

It points to a file managed by systemd-resolved. The service monitors and regenerates this file. The corruption did not persist because systemd-resolved restored it. To truly break DNS, the service itself must be stopped first:

```bash
sudo systemctl stop systemd-resolved
```

**Fix:**
```bash
sudo systemctl start systemd-resolved
```

**What this teaches:** Understanding who owns a file matters before trying to modify it. Writing to a symlink managed by a running service is fighting the system rather than working with it. The OS is not passive — services are actively managing state.

---

## Traceroute — Durban to Google

```bash
traceroute google.com
```

```
traceroute to google.com (192.178.54.46), 64 hops max
 1   10.0.2.2           0.487ms   0.376ms   0.378ms
 2   10.143.208.130     2.158ms   2.661ms   1.961ms
 3   *  *  *
 4   *  *  10.242.200.129    26.272ms
 5   10.242.200.193    36.609ms   21.947ms   10.251.60.149   18.774ms
 6   10.251.60.149     26.931ms   28.025ms   22.247ms
 7   10.113.145.33     20.615ms   16.239ms   10.251.60.150   26.931ms
 8   *  10.113.145.33   47.932ms  *
 9   *  192.168.133.110  70.437ms  *
10   192.168.133.110   54.387ms   21.574ms   21.580ms
11   41.21.235.25      20.577ms   19.463ms   22.619ms
12   72.14.213.250     45.257ms   33.318ms   10.118.24.61    31.272ms
13   72.14.213.250     36.910ms   31.627ms   40.631ms
14   172.253.73.109    27.113ms   192.178.99.199   28.658ms   31.151ms
15   192.178.54.46     37.515ms   34.540ms   172.253.73.105  33.845ms
```

### Reading the output

| Hop | IP | What it is |
|---|---|---|
| 1 | 10.0.2.2 | VirtualBox NAT gateway — first door out of the VM |
| 2 | 10.143.208.130 | Home router or ISP first hop — packet enters the real internet |
| 3 | * * * | Silent router — configured to ignore traceroute, packet still passed through |
| 11 | 41.21.235.25 | South African infrastructure — packet still in SA |
| 12-13 | 72.14.213.250 | Google's network — packet has arrived at the destination infrastructure |
| 15 | 192.178.54.46 | Google — destination reached in 37ms from Durban |

**15 hops. 37 milliseconds. Durban to Google.**

### What the * * * means

Silent hops are not broken hops. Routers configured to not respond to traceroute probes show as * * *. As long as the next hop responds, the packet is moving. Only consecutive * * * all the way to the end indicates a genuine failure. A router choosing not to announce itself is a security practice, not a network fault.

---

## Key Networking Concepts Understood

**The path a packet takes to reach its destination:**

```
Application produces data
        |
        v
Transport layer adds port numbers (TCP/UDP)
        |
        v
Network layer adds IP addresses, consults routing table
        |
        v
Data link layer resolves IP to MAC via ARP
        |
        v
Physical layer transmits bits on the wire
```

Each layer adds information on the way out and strips it on the way in at the destination. tcpdump operates at the boundary between the data link and network layers — it sees everything above that point.

**The difference between connectivity problems:**

| Symptom | Likely cause | Layer |
|---|---|---|
| Cannot reach anything | Interface down or no default route | Layer 2 or 3 |
| Cannot reach external IPs | Default route missing | Layer 3 |
| IP works, hostname does not | DNS broken | Application layer |
| Cannot reach specific host | Firewall or route missing | Layer 3 or 4 |
| Connection refused | Service not running or wrong port | Application layer |
| Connection timeout | Firewall dropping packets silently | Layer 3 or 4 |

This table is the diagnostic framework that emerged from deliberately breaking and fixing the network during this phase.
