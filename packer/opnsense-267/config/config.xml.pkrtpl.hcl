<?xml version="1.0"?>
<!--
  ===========================================================================
  fw-01 seed configuration  —  rendered by Packer, imported during the build
  ===========================================================================

  WHAT THIS FILE IS
    A Packer template (`templatefile()`) that renders OPNsense's /conf/config.xml.
    Packer bakes the rendered file into a tiny ISO9660 volume labelled OPNCFG,
    attaches it as a second CD, and the boot_command copies it over
    /conf/config.xml on the freshly installed system. When fw-01 first boots,
    this is its entire configuration: interfaces, DHCP, firewall rules, IDS.

  WHY IT IS A TEMPLATE AND NOT A CHECKED-IN config.xml
    Because the MACs and addresses in here also appear in lab.yaml and in
    OpenTofu's network_device blocks. Hand-copying them into a static XML file
    is how a DHCP reservation silently stops matching the VM it was written
    for. One source, rendered twice, cannot drift.

  ⚠️ HONEST WARNING ABOUT THIS FILE'S ACCURACY
    OPNsense's config.xml is an internal model store, not a documented public
    schema, and element names move between releases. This file was written
    offline, from the documented model layout, and has NOT been diffed against
    a real 26.7 export. Treat it as a strong starting point, not gospel.

    The correct way to make it authoritative, and the way a real engineer
    should do it once the host exists:

      1. Build fw-01 once by hand from this template.
      2. Finish the config in the GUI until the lab actually works.
      3. System > Configuration > Backups > Download configuration.
      4. Diff the export against this file and adopt the export's element
         names, replacing the lab-specific values with the $${...} markers.

    Two areas are the most likely to need that treatment:
      * DHCP.  OPNsense removed the legacy ISC dhcpd; DHCPv4 now lives under
        <OPNsense><Kea><dhcp4>. The Kea block below follows that model. If a
        26.7 export shows Dnsmasq as the active DHCP backend instead, the
        pool and the reservations move, but the VALUES stay the same.
      * <IDS>.  The core Intrusion Detection (Suricata) model version attribute
        changes almost every release; OPNsense migrates it forward on boot.
        (Suricata is core in 26.7 — base `suricata` package, no os-suricata
        plugin. The version below may migrate on first boot.)

    XML comments in this file survive only until OPNsense first rewrites
    config.xml, which it does on the first configuration change. The comments
    are for the person reading the repository, not for the running firewall.

  SECRETS
    Nothing secret is hardcoded here. The root password arrives as a crypt hash
    from an environment variable, and the WAN address — the one genuinely
    sensitive value in this lab — is either DHCP or comes from a sensitive
    Packer variable that is never committed.
-->
<opnsense>
  <!--
    No <version> element is emitted on purpose. OPNsense treats a missing or
    older config version as "needs migration" and runs its migration chain on
    first boot, which fills in whatever defaults this release expects. Pinning
    a version we guessed would suppress exactly the fix-up we want.
  -->
  <theme>opnsense</theme>

  <system>
    <hostname>${fw_hostname}</hostname>
    <domain>${lab_domain}</domain>
    <timezone>${timezone}</timezone>
    <language>en_US</language>
    <optimization>normal</optimization>

    <!--
      fw-01 is the lab's NTP server. Every Wazuh alert, every Windows security
      event and every Suricata alert is eventually correlated on timestamp, so
      the firewall's clock is a security control, not a convenience.
    -->
    <timeservers>pool.ntp.org</timeservers>

    <!--
      The firewall resolves for ITSELF using a public resolver. It does NOT
      point at dc-01: on a cold start dc-01 does not exist yet, and a firewall
      that cannot resolve its own package mirror cannot be updated. Lab clients
      are pointed at dc-01 by DHCP instead, further down.
    -->
    <dnsserver>${upstream_dns}</dnsserver>
    <dnsallowoverride>0</dnsallowoverride>

    <group>
      <name>admins</name>
      <description>System Administrators</description>
      <scope>system</scope>
      <gid>1999</gid>
      <member>0</member>
      <priv>page-all</priv>
    </group>

    <user>
      <name>root</name>
      <descr>System Administrator</descr>
      <scope>system</scope>
      <groupname>admins</groupname>
      <!--
        Importing a config replaces the user database, which is why the build
        has to know the password twice: once as plaintext for the installer's
        console prompt, once as a hash for this element.
      -->
      <password>${root_password_hash}</password>
      <uid>0</uid>
    </user>
    <nextuid>2000</nextuid>
    <nextgid>2000</nextgid>

    <webgui>
      <protocol>https</protocol>
    </webgui>

    <!--
      SSH is enabled with root login so that Ansible can manage this firewall
      the same way it manages every other host in the lab. On a production
      firewall this would be key-only with a non-root account; here the whole
      machine is rebuilt from this template on demand, which changes the
      trade-off. Worth saying out loud rather than leaving as an accident.
    -->
    <ssh>
      <enabled>enabled</enabled>
      <permitrootlogin>1</permitrootlogin>
      <passwordauth>1</passwordauth>
      <interfaces>lan</interfaces>
    </ssh>

    <!--
      Plugins are tracked in the config, not just on disk. The build installs
      os-qemu-guest-agent with pkg; if this list did not name it, a later
      firmware sync could decide it is a stray and remove it.

      os-qemu-guest-agent is not optional: the bpg provider's agent.enabled is
      true for every VM in this lab, and without a running guest agent every
      create AND every refresh blocks for fifteen minutes.

      NOTE (corrected 2026-07-22): os-suricata was ALSO listed here, but no such
      plugin exists in OPNsense 26.7 — Intrusion Detection is a core feature and
      Suricata is the base `suricata` package, configured through <OPNsense><IDS>
      below. Listing a non-existent plugin here invites a firmware audit to keep
      trying to reconcile it, so it is removed. See the pkg step's comment in
      opnsense.pkr.hcl.
    -->
    <firmware version="1.0.1">
      <mirror/>
      <flavour/>
      <plugins>os-qemu-guest-agent</plugins>
      <type/>
      <subscription/>
      <reboot/>
    </firmware>
  </system>

  <!--
    =========================================================================
    Interfaces
    =========================================================================
    VirtIO NICs enumerate as vtnetN in PCI order, and OpenTofu attaches fw-01's
    three NICs in the order vmbr0, vmbr1, vmbr2. So:

      vtnet0 -> vmbr0  WAN       (management/uplink; address is a secret)
      vtnet1 -> vmbr1  SOC LAN   10.10.10.1/24
      vtnet2 -> vmbr2  ISOLATED  10.10.20.1/24   (OPT1)

    If a future change reorders those network_device blocks, the firewall will
    happily route the isolated network onto the management LAN. The ordering is
    load-bearing.
  -->
  <interfaces>
    <wan>
      <if>${wan_if}</if>
      <descr>WAN</descr>
      <enable>1</enable>
      <lock>1</lock>
      <!--
        blockpriv and blockbogons are OFF, which looks wrong on a WAN and is
        deliberate. This "WAN" faces vmbr0, a private RFC1918 management LAN,
        not the internet. blockpriv would drop new inbound connections from the
        very network the operator administers the lab from, and the bogon list
        is a cron-fetched file that buys nothing on a private uplink. On a
        genuinely internet-facing firewall both belong at 1.
      -->
      <blockpriv>0</blockpriv>
      <blockbogons>0</blockbogons>
%{ if wan_mode == "dhcp" ~}
      <ipaddr>dhcp</ipaddr>
      <dhcphostname/>
%{ else ~}
      <ipaddr>${wan_address}</ipaddr>
      <subnet>${wan_prefix}</subnet>
      <gateway>WAN_GW</gateway>
%{ endif ~}
      <spoofmac/>
    </wan>

    <lan>
      <if>${lan_if}</if>
      <descr>SOCLAN</descr>
      <enable>1</enable>
      <lock>1</lock>
      <ipaddr>${lan_address}</ipaddr>
      <subnet>${lan_prefix}</subnet>
      <spoofmac/>
    </lan>

    <opt1>
      <if>${isolated_if}</if>
      <descr>ISOLATED</descr>
      <enable>1</enable>
      <ipaddr>${isolated_address}</ipaddr>
      <subnet>${isolated_prefix}</subnet>
      <spoofmac/>
    </opt1>
  </interfaces>

  <gateways>
%{ if wan_mode == "static" ~}
    <gateway_item>
      <interface>wan</interface>
      <gateway>${wan_gateway}</gateway>
      <name>WAN_GW</name>
      <descr>Upstream gateway</descr>
      <defaultgw>1</defaultgw>
      <ipprotocol>inet</ipprotocol>
    </gateway_item>
%{ endif ~}
  </gateways>

  <!--
    Outbound NAT in automatic mode. Both 10.10.10.0/24 and 10.10.20.0/24 are
    translated behind the WAN address, which is what lets a lab VM reach the
    internet without the upstream router knowing the lab's internal topology.
  -->
  <nat>
    <outbound>
      <mode>automatic</mode>
    </outbound>
  </nat>

  <!--
    =========================================================================
    Firewall rules — evaluated top to bottom, first match wins
    =========================================================================
  -->
  <filter>
    <!--
      ★ THE RULE THAT LOOKS WRONG AND IS NOT ★

      An explicit pass for dc-01 (${dc_address}) out to anywhere.

      Windows Server 2022 Evaluation is a 180-day licence that MUST activate
      over the internet within the first TEN DAYS or the machine begins
      shutting itself down. On vmbr1 there is no route out except through this
      firewall, so if this rule is missing the domain controller quietly dies
      about a week and a half into the semester and takes the AD labs with it.

      It sits FIRST so that a learner who tightens the general LAN rule below —
      which is a perfectly reasonable exercise — does not take the DC out as a
      side effect. It is redundant while the permissive rule below exists. That
      redundancy is the point: it is a seatbelt for a rule that is expected to
      change.

      This is also the one place where "isolated lab" is not true, and that
      tension is worth teaching rather than hiding.
    -->
    <rule>
      <type>pass</type>
      <ipprotocol>inet</ipprotocol>
      <interface>lan</interface>
      <statetype>keep state</statetype>
      <descr>dc-01 outbound: Windows Server evaluation must activate within 10 days</descr>
      <source>
        <address>${dc_address}</address>
      </source>
      <destination>
        <any>1</any>
      </destination>
    </rule>

    <!--
      General SOC LAN egress. Permissive on purpose in v1: the endpoints need
      Windows Update, Wazuh agents need the manager, and analysts need the
      internet. Tightening this is a designed exercise, not an oversight.
    -->
    <rule>
      <type>pass</type>
      <ipprotocol>inet</ipprotocol>
      <interface>lan</interface>
      <statetype>keep state</statetype>
      <descr>SOC LAN to any (lab default; tighten as an exercise)</descr>
      <source>
        <network>lan</network>
      </source>
      <destination>
        <any>1</any>
      </destination>
    </rule>

    <!--
      This block is what makes vmbr2 "isolated". It must come BEFORE the
      permissive rule underneath it, or kali-01 can walk straight onto the
      SOC LAN and the segmentation is decorative.
    -->
    <rule>
      <type>block</type>
      <ipprotocol>inet</ipprotocol>
      <interface>opt1</interface>
      <descr>ISOLATED must not reach the SOC LAN — this is the segmentation</descr>
      <source>
        <network>opt1</network>
      </source>
      <destination>
        <network>lan</network>
      </destination>
    </rule>

    <!--
      Isolated hosts still need the internet: kali-01 needs `apt update`, and
      nlp-01 pulls models. "Isolated" here means isolated from the monitored
      estate, not airgapped. Say which one you mean when you teach it.
    -->
    <rule>
      <type>pass</type>
      <ipprotocol>inet</ipprotocol>
      <interface>opt1</interface>
      <statetype>keep state</statetype>
      <descr>ISOLATED to internet (package updates); SOC LAN already blocked above</descr>
      <source>
        <network>opt1</network>
      </source>
      <destination>
        <any>1</any>
      </destination>
    </rule>
  </filter>

  <!--
    Unbound is present but NOT enabled (no <enable> element).

    The lab's authoritative resolver is dc-01 at ${dc_address}, because AD
    clients need SRV records that only the DC serves. If the firewall also
    answered DNS on the LAN, a client that ignored the DHCP option would still
    resolve — just without any Active Directory records — and the failure would
    look like "DNS works but the domain join fails", which is a genuinely
    horrible thing to debug. Leaving it off makes that failure loud.
  -->
  <unbound>
    <dnssec>1</dnssec>
  </unbound>

  <OPNsense>
    <!--
      =====================================================================
      DHCPv4 (Kea)
      =====================================================================
      The pool and options reproduce the as-built lab recorded in
      docs/network/dhcp-validation.md: 10.10.10.100-200, gateway 10.10.10.1,
      DNS 10.10.10.10, domain mutaspace.local.

      DNS points at dc-01 and not at the firewall. That single option is what
      makes domain join work for every machine that gets an address here.

      The reservations below are keyed on MACs that are pinned in lab.yaml and
      handed to Proxmox by OpenTofu. Because both sides read the same map,
      analyst-01 is on .50 and win-client-01 is on .51 after a full rebuild
      without anyone touching the firewall.

      The list is DERIVED, in opnsense.pkr.hcl, by reading lab.yaml directly -
      it is not typed out anywhere. That matters: the per-learner Windows
      clients are DHCP machines too (.60, .62, .64 with learner_count = 3), and
      a hand-maintained list is exactly how three of them once ended up with a
      pinned MAC on the hypervisor and no reservation here.
    -->
    <Kea>
      <ctrl_agent version="1.0.0">
        <general>
          <enabled>0</enabled>
        </general>
      </ctrl_agent>
      <dhcp4 version="1.0.1">
        <general>
          <enabled>1</enabled>
          <interfaces>lan</interfaces>
          <valid_lifetime>4000</valid_lifetime>
          <!-- Let Kea manage the pass rules for DHCP itself. -->
          <fwrules>1</fwrules>
        </general>
        <ha>
          <enabled>0</enabled>
        </ha>
        <subnets>
          <subnet4 uuid="${dhcp_subnet_uuid}">
            <subnet>${lan_network}</subnet>
            <description>SOC LAN</description>
            <option_data>
              <routers>${lan_address}</routers>
              <domain_name_servers>${dc_address}</domain_name_servers>
              <domain_name>${lab_domain}</domain_name>
              <ntp_servers>${lan_address}</ntp_servers>
            </option_data>
            <pools>${lan_dhcp_from}-${lan_dhcp_to}</pools>
          </subnet4>
        </subnets>
        <reservations>
%{ for r in dhcp_reservations ~}
          <reservation uuid="${r.uuid}">
            <subnet>${dhcp_subnet_uuid}</subnet>
            <hw_address>${r.mac}</hw_address>
            <ip_address>${r.address}</ip_address>
            <hostname>${r.hostname}</hostname>
            <description>Pinned in lab.yaml; MAC is an input, not a Proxmox output</description>
          </reservation>
%{ endfor ~}
        </reservations>
      </dhcp4>
    </Kea>

    <!--
      =====================================================================
      Suricata (decision D-04)
      =====================================================================
      Suricata runs HERE, on the firewall, instead of on a dedicated sensor-01
      VM. The reason is not convenience: a plain Linux bridge does not mirror.
      A promiscuous NIC hung off vmbr1 will never see unicast traffic between
      two other VMs on vmbr1, so the "obvious" sensor design silently sees
      almost nothing. Putting the sensor where the packets already have to go
      sidesteps mirroring completely.

      ★ THE LIMITATION, STATED PLAINLY ★
      This placement sees only traffic that CROSSES the firewall. It does not
      see east-west traffic. An attack from win-client-01 against
      ubuntu-app-01 — both on vmbr1, both talking directly over the bridge —
      is completely invisible to it. That is a real detection gap, and it is
      documented rather than papered over because sensor placement is the
      actual skill being taught here: the tool matters less than where you put
      it. Host-based Wazuh agents are what covers the gap in the meantime.

      The upgrade path is Open vSwitch with a mirror port feeding a real
      sensor-01. It is deferred because it changes host networking, and host
      networking changes are the ones most likely to break a class in progress.
    -->
    <IDS version="1.4.0">
      <rules/>
      <policies/>
      <userDefinedRules/>
      <files/>
      <fileTags/>
      <general>
        <enabled>${suricata_enabled}</enabled>
        <ips>${suricata_ips_mode}</ips>
        <promisc>0</promisc>
        <interfaces>${suricata_interfaces}</interfaces>
        <homenet>${lan_network},${isolated_network}</homenet>
        <defaultPacketSize/>
        <UpdateCron/>
        <AlertLogrotate>W0D23</AlertLogrotate>
        <AlertSaveLogs>4</AlertSaveLogs>
        <MPMAlgo>ac</MPMAlgo>
        <detect>
          <Profile>medium</Profile>
          <toclient_groups/>
          <toserver_groups/>
        </detect>
        <syslog>0</syslog>
        <syslog_eve>0</syslog_eve>
        <LogPayload>0</LogPayload>
        <verbosity/>
      </general>
    </IDS>
  </OPNsense>

  <syslog/>
  <widgets/>
  <revision>
    <username>packer@${fw_hostname}</username>
    <description>Seeded by packer/opnsense-267 for OPNsense ${opnsense_version}</description>
  </revision>
</opnsense>
