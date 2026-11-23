# TryHackMe room listing — Redline Forge: ForgeTrack

Public-facing listing copy. No flags or spoilers.

## Room basics

| Field | Value |
|---|---|
| Room name | **Redline Forge: ForgeTrack** |
| Difficulty | **Medium** (use Easy if aimed at first-time learners) |
| Room type | **Challenge** (CTF-style, flag submission) |
| Estimated time | **60–90 minutes** |
| Free/Premium | **Free** |
| Target OS | **Linux (Ubuntu 20.04.6 LTS)** |
| Stack | Nginx → Gunicorn → Flask 2.3.3 (Python 3.8) → PostgreSQL 12.22 |
| Credentials needed | **None for the challenges** |
| Prerequisites | Basic Linux CLI, HTTP requests, and SQL `SELECT`/`UNION` basics |

## Room settings form

| Field | Value |
|---|---|
| Title | **Redline Forge: ForgeTrack** |
| Room code | **redlineforge** (keep as-is; changing it breaks shared links) |
| Description | See the 239-character version below |
| Completion time | **120 minutes** (use 90 if you want a tighter estimate) |
| Status | **Not Submitted** until final QA is complete |
| Difficulty | **Medium** |
| Enable cloning | **Off** (only enable for event reuse) |
| Access | **Publicly accessible** for a community release; **Private** for a cohort |
| Teams | **Off** for solo learning; **On** only for a competition |
| Enable reset progress | **On** |
| Simple room | **Off** |
| Type | **Challenge** |
| Who can join? | **Free** (use Business-only/Cloud add-on only for those delivery channels) |
| Lock room | **Off** (enable only for a pre-event assessment) |
| Scoring type | **Points only (no first bloods)** |
| Remove connection options | **Off** — learners must connect to the target VM |

If the room is private, use this message:

> This room is part of the Redline Forge internship programme. Access is restricted to the current cohort and will be opened after review.

## Short description (239 characters — fits THM's 250 limit)

> Investigate Redline Forge, a motorsport platform with critical flaws. Exploit visible and blind SQL injection, turn command injection into a shell, escalate to root, and verify the fix. Built for aspiring penetration testers and defenders.

## Long description

Redline Forge Motorsport runs ForgeTrack, a fictional build, fleet, and telemetry platform. Suspicious activity has been reported and you are authorised to assess the public-facing application.

Start by mapping the site and capturing normal responses. Identify the inputs that reach the database, then progress from visible SQL injection to UNION-based extraction and blind boolean inference. After recovering the web objectives, investigate the diagnostics feature for a route onto the host, enumerate your privileges, and escalate to root.

The room closes with a remediation check: replay the original payload against the parameterised route and explain why it no longer changes the query structure.

**Learning objectives**

- Map a web application and establish normal request baselines.
- Identify and exploit string- and numeric-context SQL injection.
- Reason about column counts and use `UNION` to extract data.
- Exploit a boolean blind oracle without timing attacks.
- Turn command injection into a reverse shell.
- Enumerate and abuse a weak `sudo` rule for Linux privilege escalation.
- Verify a parameterised fix and explain secure coding remediation.

## Categories and tags

Use the closest available label if the picker does not contain the exact string.

### General

```text
Web
Linux
SQL Injection
Boot2Root
Web Application Security
Challenge
Beginner Friendly
```

### Job Roles

```text
Penetration Tester
Application Security Engineer
Security Engineer
Red Teamer
```

### PoV

```text
Attacker
Defender
```

Choose **Attacker** if PoV is single-select. Defender reflects the remediation objective.

### Segment

```text
Education
Academia
Enterprise
Automotive
Motorsport
```

Drop any that are not offered; **Education** + **Enterprise** are the safest fallbacks.

### Skills

```text
SQL Injection
UNION SQL Injection
Blind SQL Injection
Boolean-Based Blind SQL Injection
Command Injection
OS Command Injection
Linux Privilege Escalation
Sudo Misconfiguration
Web Application Enumeration
Reverse Shell
Secure Coding
Remediation
```

Pick 6–10 of these if the UI limits tag count.

### Technology

```text
Linux
Ubuntu
Nginx
Gunicorn
Flask
Python
PostgreSQL
SQL
Docker
HTTP
```

### Tools

```text
Burp Suite
curl
Browser Developer Tools
sqlmap
Nmap
Netcat
SSH
Python 3
sudo
```

`sqlmap`, `Docker`, and `Nmap` are optional depending on the intended learner path.

## MITRE category tags

### Add these

| Technique | ID | Tactic |
|---|---|---|
| Exploit Public-Facing Application | **T1190** | Initial Access |
| Command and Scripting Interpreter: Unix Shell | **T1059.004** | Execution |
| Exploitation for Privilege Escalation | **T1068** | Privilege Escalation |
| Abuse Elevation Control Mechanism: Sudo and Sudo Caching | **T1548.003** | Privilege Escalation |

### Optional additions

| Technique | ID | Tactic |
|---|---|---|
| Network Service Discovery | T1046 | Discovery |
| System Information Discovery | T1082 | Discovery |
| Data from Local System | T1005 | Collection |
| Data from Information Repositories | T1213 | Collection |
| Remote Services: SSH | T1021.004 | Lateral Movement |

### Do not add these

The following were pasted from the browse list and do not apply to this Linux web lab:

- T1199 Trusted Relationship
- T1106 Native API
- T1047 Windows Management Instrumentation
- T1098 Account Manipulation
- T1176 Browser Extensions
- T1055 Process Injection
- T1497 Virtualization/Sandbox Evasion
- T1217 Browser Bookmark Discovery
- T1080 Taint Shared Content
- T1113 Screen Capture

## Notes

- Keep tags consistent with the final room title and description.
- Don't tag every sub-technique; the four primary MITRE entries cover the intended chain.
- Do not put flags, credentials, or route names that give away the solution in the public listing.
