# =============================================================================
# snippets.tf - per-VM cloud-init payloads, uploaded to the Proxmox host
# =============================================================================
#
# WHAT A SNIPPET IS
#   A file in /var/lib/vz/snippets on the Proxmox node that a VM's cloud-init drive
#   points at. Proxmox calls it `cicustom`, and it lets a VM be handed arbitrary
#   user-data instead of the small generated stub Proxmox would otherwise produce.
#
# THE PART THAT SURPRISES PEOPLE
#   Snippets cannot be uploaded through the Proxmox API. The storage upload
#   endpoint only accepts iso, vztmpl and import content types - snippets are not
#   on the list. The provider quietly falls back to SFTP over SSH, which means
#   these resources need a real Linux account on the node with a key in the
#   operator's ssh-agent, not just an API token. See providers.tf.
#
#   The `snippets` content type also has to be enabled on the datastore first:
#     pvesm set local --content iso,vztmpl,backup,snippets
#   It is off by default, and without it every resource in this file fails.
#
# WHY THE FILENAMES ARE STABLE AND BORING
#   `initialization.user_data_file_id` is ForceNew. That creates a genuine
#   two-horned choice and both horns hurt:
#
#     (a) keep the filename constant - editing the snippet's CONTENT updates the
#         file on the host but does NOT recreate the VM, so cloud-init never re-runs
#         and the change is invisible until the machine is rebuilt; or
#     (b) version the filename with a content hash - every edit destroys and
#         recreates the VM.
#
#   This lab takes (a). Cloud-init is first-boot configuration; anything that needs
#   to change on a running machine is Ansible's job, which is re-runnable by design.
#   A snippet edit is therefore treated as something that takes effect at the next
#   deliberate rebuild, which is also the honest description of what it is.
#

# -----------------------------------------------------------------------------
# user-data
# -----------------------------------------------------------------------------
# One resource covering both guest families, because they differ only in which
# template gets rendered. Appliances (fw-01) are excluded upstream in locals.tf -
# OPNsense has no cloud-init and a snippet for it would be a file nothing reads.
resource "proxmox_virtual_environment_file" "user_data" {
  for_each = local.cloud_init_vms

  content_type = "snippets"
  datastore_id = local.site.snippets_store
  node_name    = local.site.node

  source_raw {
    file_name = "${each.key}-user-data.${each.value.guest == "windows" ? "ps1" : "yaml"}"

    data = each.value.guest == "windows" ? templatefile(
      "${path.module}/templates/user-data-windows.tftpl",
      {
        hostname = each.key
        fqdn     = "${each.key}.${local.site.domain}"
        role     = each.value.role

        # Rendered straight into a PowerShell array literal, so each server has to
        # arrive already quoted: 'a', 'b'.
        dns_servers = join(", ", [for s in local.vm_dns_servers[each.key] : "'${s}'"])

        # The firewall is the lab's only time source. Which leg of it depends on
        # which plane the guest is on.
        ntp_server = local.network_meta[local.vm_network[each.key]].gateway
      }
      ) : templatefile(
      "${path.module}/templates/user-data-linux.tftpl",
      {
        hostname            = each.key
        fqdn                = "${each.key}.${local.site.domain}"
        role                = each.value.role
        admin_username      = local.site.admin_username
        ssh_authorized_keys = var.lab_ssh_authorized_keys
        password            = var.lab_admin_password
        timezone            = local.site.timezone
        ntp_server          = local.network_meta[local.vm_network[each.key]].gateway
      }
    )
  }
}

# -----------------------------------------------------------------------------
# meta-data (NoCloud / Linux only)
# -----------------------------------------------------------------------------
# Windows guests are absent on purpose. Cloudbase-Init reads a configdrive2 drive
# whose metadata Proxmox generates from the VM name, and that is already correct;
# overriding it would be one more thing to keep in sync for no benefit.
resource "proxmox_virtual_environment_file" "meta_data" {
  for_each = local.linux_cloud_init_vms

  content_type = "snippets"
  datastore_id = local.site.snippets_store
  node_name    = local.site.node

  source_raw {
    file_name = "${each.key}-meta-data.yaml"

    data = templatefile(
      "${path.module}/templates/meta-data.tftpl",
      {
        hostname = each.key

        # Identity, not a serial number. cloud-init re-runs its per-instance
        # modules when this changes, so tying it to the machine's identity in
        # lab.yaml makes "will this re-run?" answerable by reading the code.
        instance_id = "${each.key}-${each.value.vm_id}"
      }
    )
  }
}
