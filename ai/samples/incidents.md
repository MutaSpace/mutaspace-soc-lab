# Sample incidents for the detection copilot

Each incident below is a plain-language description an analyst might write after an
investigation. `detection_copilot.py --samples` feeds these to the model one at a time and
runs the generate → validate → repair loop on each. They are grounded in this lab's own
hosts and segments so the generated rules read like real lab detections.

Format: a `## [type] title` heading (type is `sigma` for log rules or `suricata` for
network rules) followed by the incident description. The parser reads exactly that.

## [sigma] SSH brute force against the Linux app server

Auth logs on ubuntu-app-01 (10.10.10.30) show more than 20 failed `sshd` password
attempts for the user `root` from a single source on the isolated segment within one
minute, followed by one accepted password login. Detect repeated authentication failures
from one source that culminate in a success. Log source: Linux authentication.

## [sigma] Encoded PowerShell on the Windows workstation

On win-client-01, a process-creation event shows `powershell.exe` launched with an
`-EncodedCommand` argument and a base64 blob, spawned by `winword.exe`. Detect PowerShell
executions that use encoded commands, especially when the parent is an Office application.
Log source: Windows process creation.

## [sigma] Web shell upload to the Nginx server

Webserver logs on ubuntu-app-01 show a POST to a newly-created `.php` file under the
uploads directory, followed by GET requests to that same file with a `cmd=` query
parameter. Detect requests to recently-uploaded script files that carry command
parameters. Log source: Nginx webserver.

## [suricata] Suspicious User-Agent beaconing to external host

A host on the SOC LAN is making repeated HTTP requests to an external server with the
User-Agent string "EvilBot/1.0" at a regular interval — a likely C2 beacon. Write a
network rule that alerts on outbound HTTP carrying that User-Agent. Client-to-server
traffic; classtype trojan-activity; sid 9000001.

## [suricata] DNS query for a known-bad domain

An endpoint on the SOC LAN resolves the domain "malware-c2.example" via DNS. Write a
network rule that alerts on a DNS query for that domain name. classtype
trojan-activity; sid 9000002.

## [suricata] Cleartext credential path requested over HTTP

A host is requesting the URI "/phpmyadmin/config.inc.php" over plain HTTP against a server
in $HOME_NET — a scan for an exposed credentials file. Write a network rule that alerts on
an HTTP request whose URI contains that path. Client-to-server; classtype
web-application-attack; sid 9000003.
