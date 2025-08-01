(*
 * Copyright (C) 2006-2009 Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)
(**
 * @group Command-Line Interface (CLI)
*)

(* ----------------------------------------------------------------------
   XE-CLI Front End
   ---------------------------------------------------------------------- *)

open Cli_cmdtable

module D = Debug.Make (struct let name = "cli" end)

open D

(* ---------------------------------------------------------------------
   Command table
   --------------------------------------------------------------------- *)

let vmselectors = ["<vm-selectors>"]

let vmselectorsinfo =
  " VMs can be specified by filtering the full list of VMs on the values of \
   zero or more fields. For example, specifying 'uuid=<some_uuid>' will select \
   only the VM with that uuid, and 'power-state=halted' will select only VMs \
   whose 'power-state' field is equal to 'halted'. The special pseudo-field \
   'vm' matches either of name-label or uuid. Where multiple VMs are matching, \
   the option '--multiple' must be specified to perform the operation. The \
   full list of fields that can be matched can be obtained by the command 'xe \
   vm-list params=all'. If no parameters to select VMs are given, the \
   operation will be performed on all VMs."

let hostselectors = ["<host-selectors>"]

let hostselectorsinfo =
  " Hosts can be specified by filtering the full list of hosts on the values \
   of zero or more fields. For example, specifying 'uuid=<some_uuid>' will \
   select only the host with that uuid, and 'enabled=true' will select only \
   hosts whose 'enabled' field is equal to 'true'. The special pseudo-field \
   'host' matches any of hostname, name-label or uuid. Where multiple hosts \
   are matching, and the operation can be performed on multiple hosts, the \
   option '--multiple' must be specified to perform the operation. The full \
   list of fields that can be matched can be obtained by the command 'xe \
   host-list params=all'. If no parameters to select hosts are given, the \
   operation will be performed on all hosts."

let srselectors = ["<sr-selectors>"]

let srselectorsinfo =
  " SRs can be specified by filtering the full list of SRs on the values of \
   zero or more fields. For example, specifying 'uuid=<some_uuid>' will select \
   only the sr with that uuid, and 'enabled=true' will select only srs whose \
   'enabled' field is equal to 'true'. The special pseudo-field 'sr' matches \
   either of name-label or uuid. Where multiple SRs are matching, and the \
   operation can be performed on multiple SRs, the option '--multiple' must be \
   specified to perform the operation. The full list of fields that can be \
   matched can be obtained by the command 'xe sr-list params=all'. If no \
   parameters to select SRs are given, the operation will be performed on all \
   SRs."

let rec cmdtable_data : (string * cmd_spec) list =
  [
    ( "blob-get"
    , {
        reqd= ["uuid"; "filename"]
      ; optn= []
      ; help= "Save the binary blob to the local filesystem"
      ; implementation= With_fd Cli_operations.blob_get
      ; flags= [Hidden]
      }
    )
  ; ( "blob-put"
    , {
        reqd= ["uuid"; "filename"]
      ; optn= []
      ; help= "Upload a binary blob to the xapi server"
      ; implementation= With_fd Cli_operations.blob_put
      ; flags= [Hidden]
      }
    )
  ; ( "blob-create"
    , {
        reqd= ["name"]
      ; optn=
          [
            "mime-type"
          ; "vm-uuid"
          ; "host-uuid"
          ; "sr-uuid"
          ; "network-uuid"
          ; "pool-uuid"
          ; "public"
          ]
      ; help= "Create a binary blob to be associated with an API object"
      ; implementation= No_fd Cli_operations.blob_create
      ; flags= [Hidden]
      }
    )
  ; ( "message-create"
    , {
        reqd= ["name"; "priority"; "body"]
      ; optn= ["vm-uuid"; "host-uuid"; "sr-uuid"; "pool-uuid"]
      ; help=
          "Create a message associated with a particular API object. Note \
           exactly one of the optional parameters must be supplied."
      ; implementation= No_fd Cli_operations.message_create
      ; flags= []
      }
    )
  ; ( "message-destroy"
    , {
        reqd= []
      ; optn= ["uuid"; "uuids"]
      ; help= "Destroy one existing message or many"
      ; implementation= No_fd Cli_operations.message_destroy
      ; flags= []
      }
    )
  ; ( "pool-enable-binary-storage"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Enable the storage of binary data, including RRDs, messages and \
           blobs."
      ; implementation= No_fd Cli_operations.pool_enable_binary_storage
      ; flags= [Hidden]
      }
    )
  ; ( "pool-disable-binary-storage"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Disable the storage of binary data. This will destroy any messages, \
           RRDs and blobs stored across the pool."
      ; implementation= No_fd Cli_operations.pool_disable_binary_storage
      ; flags= [Hidden]
      }
    )
  ; ( "pool-designate-new-master"
    , {
        reqd= ["host-uuid"]
      ; optn= []
      ; help=
          "Request an orderly handover of the role of master to another host."
      ; implementation= No_fd Cli_operations.pool_designate_new_master
      ; flags= []
      }
    )
  ; ( "pool-management-reconfigure"
    , {
        reqd= ["network-uuid"]
      ; optn= []
      ; help=
          "Reconfigure the management network interface for all Hosts in the \
           Pool"
      ; implementation= No_fd Cli_operations.pool_management_reconfigure
      ; flags= []
      }
    )
  ; ( "pool-sync-database"
    , {
        reqd= []
      ; optn= []
      ; help= "Synchronise the current database across all hosts in the pool."
      ; implementation= No_fd Cli_operations.pool_sync_database
      ; flags= []
      }
    )
  ; ( "pool-join"
    , {
        reqd= ["master-address"; "master-username"; "master-password"]
      ; optn= ["force"]
      ; help= "Instruct host to join an existing pool."
      ; implementation= No_fd Cli_operations.pool_join
      ; flags= []
      }
    )
  ; ( "pool-emergency-reset-master"
    , {
        reqd= ["master-address"]
      ; optn= []
      ; help= "Instruct slave to reset master address."
      ; implementation=
          No_fd_local_session Cli_operations.pool_emergency_reset_master
      ; flags= [Neverforward]
      }
    )
  ; ( "pool-emergency-transition-to-master"
    , {
        reqd= []
      ; optn= ["force"]
      ; help=
          "Instruct slave to become pool master. The operation will be ignored \
           if this host is already master; the optional parameter '--force' \
           will force the operation."
      ; implementation=
          No_fd_local_session Cli_operations.pool_emergency_transition_to_master
      ; flags= [Neverforward]
      }
    )
  ; ( "pool-recover-slaves"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Instruct master to try and reset master-address of all slaves \
           currently running in emergency mode."
      ; implementation= No_fd Cli_operations.pool_recover_slaves
      ; flags= []
      }
    )
  ; ( "pool-eject"
    , {
        reqd= ["host-uuid"]
      ; optn= []
      ; help= "Instruct host to leave an existing pool."
      ; implementation= With_fd Cli_operations.pool_eject
      ; flags= []
      }
    )
  ; ( "pool-dump-database"
    , {
        reqd= ["file-name"]
      ; optn= []
      ; help= "Download a dump of the pool database."
      ; implementation= With_fd Cli_operations.pool_dump_db
      ; flags= []
      }
    )
  ; ( "pool-restore-database"
    , {
        reqd= ["file-name"]
      ; optn= ["dry-run"]
      ; help= "Restore a dump of the pool database to the server."
      ; implementation= With_fd Cli_operations.pool_restore_db
      ; flags= []
      }
    )
  ; ( "pool-enable-external-auth"
    , {
        reqd= ["auth-type"; "service-name"]
      ; optn= ["uuid"; "config:"]
      ; help=
          "Enables external authentication in all the hosts in a pool. Note \
           that some values of auth-type will require particular config: \
           values."
      ; implementation= No_fd Cli_operations.pool_enable_external_auth
      ; flags= []
      }
    )
  ; ( "pool-disable-external-auth"
    , {
        reqd= []
      ; optn= ["uuid"; "config:"]
      ; help= "Disables external authentication in all the hosts in a pool"
      ; implementation= No_fd Cli_operations.pool_disable_external_auth
      ; flags= []
      }
    )
  ; ( "pool-initialize-wlb"
    , {
        reqd=
          [
            "wlb_url"
          ; "wlb_username"
          ; "wlb_password"
          ; "xenserver_username"
          ; "xenserver_password"
          ]
      ; optn= []
      ; help=
          "Initialize workload balancing for the current pool with the target \
           wlb server"
      ; implementation= No_fd Cli_operations.pool_initialize_wlb
      ; flags= []
      }
    )
  ; ( "pool-deconfigure-wlb"
    , {
        reqd= []
      ; optn= []
      ; help= "Permanently remove the configuration for workload balancing"
      ; implementation= No_fd Cli_operations.pool_deconfigure_wlb
      ; flags= []
      }
    )
  ; ( "pool-send-wlb-configuration"
    , {
        reqd= []
      ; optn= ["config:"]
      ; help=
          "Sets the pool optimization criteria for the workload balancing \
           server"
      ; implementation= No_fd Cli_operations.pool_send_wlb_configuration
      ; flags= []
      }
    )
  ; ( "pool-retrieve-wlb-configuration"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Retrieves the pool optimization criteria from the workload \
           balancing server"
      ; implementation= No_fd Cli_operations.pool_retrieve_wlb_configuration
      ; flags= []
      }
    )
  ; ( "pool-retrieve-wlb-recommendations"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Retrieves vm migrate recommendations for the pool from the workload \
           balancing server"
      ; implementation= No_fd Cli_operations.pool_retrieve_wlb_recommendations
      ; flags= []
      }
    )
  ; ( "pool-retrieve-wlb-report"
    , {
        reqd= ["report"]
      ; optn= ["filename"]
      ; help= ""
      ; implementation= With_fd Cli_operations.pool_retrieve_wlb_report
      ; flags= [Neverforward]
      }
    )
  ; ( "pool-retrieve-wlb-diagnostics"
    , {
        reqd= []
      ; optn= ["filename"]
      ; help= ""
      ; implementation= With_fd Cli_operations.pool_retrieve_wlb_diagnostics
      ; flags= [Neverforward]
      }
    )
  ; ( "pool-send-test-post"
    , {
        reqd= ["dest-host"; "dest-port"; "body"]
      ; optn= []
      ; help=
          "Send the given body to the given host and port, using HTTPS, and \
           print the response.  This is used for debugging the SSL layer."
      ; implementation= No_fd Cli_operations.pool_send_test_post
      ; flags= []
      }
    )
  ; ( "pool-certificate-install"
    , {
        reqd= ["filename"]
      ; optn= []
      ; help= "Install a TLS CA certificate, pool-wide."
      ; implementation= With_fd Cli_operations.pool_install_ca_certificate
      ; flags= [Deprecated ["Use pool-install-ca-certificate"]]
      }
    )
  ; ( "pool-certificate-uninstall"
    , {
        reqd= ["name"]
      ; optn= []
      ; help= "Uninstall a pool-wide TLS CA certificate."
      ; implementation= No_fd Cli_operations.pool_uninstall_ca_certificate
      ; flags= [Deprecated ["Use pool-uninstall-ca-certificate"]]
      }
    )
  ; ( "pool-install-ca-certificate"
    , {
        reqd= ["filename"]
      ; optn= []
      ; help= "Install a TLS CA certificate, pool-wide."
      ; implementation= With_fd Cli_operations.pool_install_ca_certificate
      ; flags= []
      }
    )
  ; ( "pool-uninstall-ca-certificate"
    , {
        reqd= ["name"]
      ; optn= ["force"]
      ; help=
          "Uninstall a pool-wide TLS CA certificate. The optional parameter \
           '--force' will remove the DB entry even if the certificate file is \
           non-existent"
      ; implementation= No_fd Cli_operations.pool_uninstall_ca_certificate
      ; flags= []
      }
    )
  ; ( "pool-certificate-list"
    , {
        reqd= []
      ; optn= []
      ; help= "List the names of all installed TLS CA certificates."
      ; implementation= No_fd Cli_operations.pool_certificate_list
      ; flags= [Deprecated ["Use certificate-list type=ca"]]
      }
    )
  ; ( "pool-crl-install"
    , {
        reqd= ["filename"]
      ; optn= []
      ; help= "Install a TLS CA-issued Certificate Revocation List, pool-wide."
      ; implementation= With_fd Cli_operations.pool_crl_install
      ; flags= []
      }
    )
  ; ( "pool-crl-uninstall"
    , {
        reqd= ["name"]
      ; optn= []
      ; help= "Uninstall a pool-wide TLS CA-issued Certificate Revocation List."
      ; implementation= No_fd Cli_operations.pool_crl_uninstall
      ; flags= []
      }
    )
  ; ( "pool-crl-list"
    , {
        reqd= []
      ; optn= []
      ; help=
          "List the names of all installed TLS CA-issued Certificate \
           Revocation Lists."
      ; implementation= No_fd Cli_operations.pool_crl_list
      ; flags= []
      }
    )
  ; ( "pool-certificate-sync"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Copy the TLS CA certificates and CRLs of the master to all slaves."
      ; implementation= No_fd Cli_operations.pool_certificate_sync
      ; flags= []
      }
    )
  ; ( "pool-enable-tls-verification"
    , {
        reqd= []
      ; optn= []
      ; help= "Enable TLS certificate verification"
      ; implementation= No_fd Cli_operations.pool_enable_tls_verification
      ; flags= []
      }
    )
  ; ( "pool-enable-client-certificate-auth"
    , {
        reqd= ["name"]
      ; optn= []
      ; help= "Enable client certificate authentication on the pool"
      ; implementation= No_fd Cli_operations.pool_enable_client_certificate_auth
      ; flags= []
      }
    )
  ; ( "pool-disable-client-certificate-auth"
    , {
        reqd= []
      ; optn= []
      ; help= "Disable client certificate authentication on the pool"
      ; implementation=
          No_fd Cli_operations.pool_disable_client_certificate_auth
      ; flags= []
      }
    )
  ; ( "pool-set-vswitch-controller"
    , {
        reqd= ["address"]
      ; optn= []
      ; help= "Set the IP address of the vswitch controller."
      ; implementation= No_fd Cli_operations.pool_set_vswitch_controller
      ; flags= [Hidden]
      }
    )
  ; ( "pool-disable-ssl-legacy"
    , {
        reqd= []
      ; optn= ["uuid"]
      ; help= "Set ssl-legacy to False on each host."
      ; implementation= No_fd Cli_operations.pool_disable_ssl_legacy
      ; flags= [Deprecated ["Legacy SSL no longer supported"]]
      }
    )
  ; ( "pool-secret-rotate"
    , {
        reqd= []
      ; optn= []
      ; help= "Change the pool secret"
      ; implementation= No_fd Cli_operations.pool_rotate_secret
      ; flags= []
      }
    )
  ; ( "pool-sync-updates"
    , {
        reqd= []
      ; optn= ["force"; "token"; "token-id"; "username"; "password"]
      ; help= "Sync updates from remote YUM repository, pool-wide."
      ; implementation= No_fd Cli_operations.pool_sync_updates
      ; flags= []
      }
    )
  ; ( "pool-reset-telemetry-uuid"
    , {
        reqd= []
      ; optn= []
      ; help= "Assign a new UUID for the pool's telemetry data."
      ; implementation= No_fd Cli_operations.pool_reset_telemetry_uuid
      ; flags= []
      }
    )
  ; ( "pool-get-guest-secureboot-readiness"
    , {
        reqd= []
      ; optn= []
      ; help= "Return the readiness of a pool for guest SecureBoot."
      ; implementation= No_fd Cli_operations.pool_get_guest_secureboot_readiness
      ; flags= []
      }
    )
  ; ( "pool-get-cpu-features"
    , {
        reqd= []
      ; optn= []
      ; help=
          {|Prints a hexadecimal representation of the pool's physical-CPU
           features for PV and HVM VMs. These are combinations of all the
           hosts' policies and are used when starting new VMs in a pool.|}
      ; implementation= No_fd Cli_operations.pool_get_cpu_features
      ; flags= []
      }
    )
  ; ( "host-is-in-emergency-mode"
    , {
        reqd= []
      ; optn= []
      ; help= "Query the target host to discover if it is in emergency mode."
      ; implementation=
          No_fd_local_session Cli_operations.host_is_in_emergency_mode
      ; flags= [Neverforward]
      }
    )
  ; ( "host-forget"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Forget about the host without contacting it explicitly. WARNING: \
           this call is useful if the host to 'forget' is dead; however, if \
           the host is live and part of the pool, you should consider using \
           pool-eject instead."
      ; implementation= With_fd Cli_operations.host_forget
      ; flags= []
      }
    )
  ; ( "host-declare-dead"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Declare that the the host is dead without contacting it explicitly. \
           WARNING: This call is dangerous and can cause data loss if the host \
           is not actually dead"
      ; implementation= With_fd Cli_operations.host_declare_dead
      ; flags= []
      }
    )
  ; ( "host-disable"
    , {
        reqd= []
      ; optn= []
      ; help= "Disable the XE host."
      ; implementation= No_fd Cli_operations.host_disable
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-sync-data"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Synchronise the non-database data stored on the pool master with \
           the named XE host."
      ; implementation= No_fd Cli_operations.host_sync_data
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-enable"
    , {
        reqd= []
      ; optn= []
      ; help= "Enable the XE host."
      ; implementation= No_fd Cli_operations.host_enable
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-enable-local-storage-caching"
    , {
        reqd= ["sr-uuid"]
      ; optn= []
      ; help= "Enable local storage caching on the specified host"
      ; implementation= No_fd Cli_operations.host_enable_local_storage_caching
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-disable-local-storage-caching"
    , {
        reqd= []
      ; optn= []
      ; help= "Disable local storage caching on the specified host"
      ; implementation= No_fd Cli_operations.host_disable_local_storage_caching
      ; flags= [Host_selectors]
      }
    )
  ; ( "pool-enable-local-storage-caching"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Enable local storage caching across the pool"
      ; implementation= No_fd Cli_operations.pool_enable_local_storage_caching
      ; flags= []
      }
    )
  ; ( "pool-disable-local-storage-caching"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Disable local storage caching across the pool"
      ; implementation= No_fd Cli_operations.pool_disable_local_storage_caching
      ; flags= []
      }
    )
  ; ( "pool-apply-edition"
    , {
        reqd= ["edition"]
      ; optn= ["uuid"; "license-server-address"; "license-server-port"]
      ; help= "Apply an edition across the pool"
      ; implementation= No_fd Cli_operations.pool_apply_edition
      ; flags= []
      }
    )
  ; ( "pool-configure-repository-proxy"
    , {
        reqd= ["proxy-url"]
      ; optn= ["proxy-username"; "proxy-password"]
      ; help= "Configure proxy for RPM package repositories"
      ; implementation= No_fd Cli_operations.pool_configure_repository_proxy
      ; flags= []
      }
    )
  ; ( "pool-disable-repository-proxy"
    , {
        reqd= []
      ; optn= []
      ; help= "Disable the proxy for RPM package repositories"
      ; implementation= No_fd Cli_operations.pool_disable_repository_proxy
      ; flags= []
      }
    )
  ; ( "host-shutdown"
    , {
        reqd= []
      ; optn= []
      ; help= "Shutdown the XE host."
      ; implementation= No_fd Cli_operations.host_shutdown
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-reboot"
    , {
        reqd= []
      ; optn= []
      ; help= "Reboot the XE host."
      ; implementation= No_fd Cli_operations.host_reboot
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-power-on"
    , {
        reqd= []
      ; optn= []
      ; help= "Power on the XE host."
      ; implementation= No_fd Cli_operations.host_power_on
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-prepare-for-poweroff"
    , {
        reqd= []
      ; optn= []
      ; help= "Perform the necessary actions before host shutdown or reboot."
      ; implementation= No_fd Cli_operations.host_prepare_for_poweroff
      ; flags= [Hidden]
      }
    )
  ; ( "host-dmesg"
    , {
        reqd= []
      ; optn= []
      ; help= "Get xen dmesg of the XE host."
      ; implementation= No_fd Cli_operations.host_dmesg
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-crashdump-upload"
    , {
        reqd= ["uuid"]
      ; optn= ["url"; "http_proxy"]
      ; help= "Upload a host crash dump to the support website."
      ; implementation= No_fd Cli_operations.host_crash_upload
      ; flags= []
      }
    )
  ; ( "host-crashdump-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Delete a host crashdump from the server."
      ; implementation= No_fd Cli_operations.host_crash_destroy
      ; flags= []
      }
    )
  ; ( "host-bugreport-upload"
    , {
        reqd= []
      ; optn= ["url"; "http_proxy"]
      ; help=
          "Upload the output of xen-bugtool --yestoall on a specific host to \
           the support website."
      ; implementation= No_fd Cli_operations.host_bugreport_upload
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-backup"
    , {
        reqd= ["file-name"]
      ; optn= []
      ; help= "Download a backup of the host's control domain."
      ; implementation= With_fd Cli_operations.host_backup
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-restore"
    , {
        reqd= ["file-name"]
      ; optn= []
      ; help= "Upload a backup of the host's control domain."
      ; implementation= With_fd Cli_operations.host_restore
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-logs-download"
    , {
        reqd= []
      ; optn= ["file-name"]
      ; help= "Download a copy of the host logs."
      ; implementation= With_fd Cli_operations.host_logs_download
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-signal-networking-change"
    , {
        reqd= []
      ; optn= []
      ; help= "Signal that networking ."
      ; implementation=
          No_fd_local_session Cli_operations.host_signal_networking_change
      ; flags= [Neverforward; Hidden]
      }
    )
  ; ( "host-send-debug-keys"
    , {
        reqd= ["host-uuid"; "keys"]
      ; optn= []
      ; help= "Send specified hypervisor debug keys to specified host"
      ; implementation= No_fd_local_session Cli_operations.host_send_debug_keys
      ; flags= []
      }
    )
  ; ( "host-notify"
    , {
        reqd= ["type"]
      ; optn= ["params"]
      ; help= "Notify some event."
      ; implementation= No_fd_local_session Cli_operations.host_notify
      ; flags= [Neverforward; Hidden]
      }
    )
  ; ( "host-syslog-reconfigure"
    , {
        reqd= ["host-uuid"]
      ; optn= []
      ; help= "Reconfigure syslog daemon."
      ; implementation= No_fd Cli_operations.host_syslog_reconfigure
      ; flags= []
      }
    )
  ; ( "host-emergency-management-reconfigure"
    , {
        reqd= ["interface"]
      ; optn= []
      ; help=
          "Reconfigure the management interface of this node: only use if the \
           node is in emergency mode."
      ; implementation=
          No_fd_local_session
            Cli_operations.host_emergency_management_reconfigure
      ; flags= [Neverforward]
      }
    )
  ; ( "host-emergency-ha-disable"
    , {
        reqd= []
      ; optn= ["force"; "soft"]
      ; help=
          "Disable HA on the local host. Only to be used to recover a pool \
           with a broken HA setup."
      ; implementation=
          No_fd_local_session Cli_operations.host_emergency_ha_disable
      ; flags= [Neverforward]
      }
    )
  ; ( "host-emergency-reset-server-certificate"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Deletes the current TLS server certificate in the host and installs \
           a new, self-signed one."
      ; implementation=
          No_fd_local_session
            Cli_operations.host_emergency_reset_server_certificate
      ; flags= [Neverforward]
      }
    )
  ; ( "host-emergency-disable-tls-verification"
    , {
        reqd= []
      ; optn= []
      ; help= "Disable TLS verification for this host only."
      ; implementation=
          No_fd_local_session
            Cli_operations.host_emergency_disable_tls_verification
      ; flags= [Neverforward]
      }
    )
  ; ( "host-emergency-reenable-tls-verification"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Reenable TLS verification for this host only, and only after it was \
           emergency disabled."
      ; implementation=
          No_fd_local_session
            Cli_operations.host_emergency_reenable_tls_verification
      ; flags= [Neverforward]
      }
    )
  ; ( "host-reset-server-certificate"
    , {
        reqd= []
      ; optn= []
      ; flags= [Host_selectors]
      ; help=
          "Deletes the current TLS server certificate in the host and installs \
           a new, self-signed one."
      ; implementation= No_fd Cli_operations.host_reset_server_certificate
      }
    )
  ; ( "host-management-reconfigure"
    , {
        reqd= ["pif-uuid"]
      ; optn= []
      ; help= "Reconfigure the management interface of this node."
      ; implementation= No_fd Cli_operations.host_management_reconfigure
      ; flags= []
      }
    )
  ; ( "host-management-disable"
    , {
        reqd= []
      ; optn= []
      ; help= "Disable the management interface of this node."
      ; implementation=
          No_fd_local_session Cli_operations.host_management_disable
      ; flags= [Neverforward]
      }
    )
  ; ( "host-compute-free-memory"
    , {
        reqd= []
      ; optn= []
      ; help= "Computes the amount of free memory on the host."
      ; implementation= No_fd Cli_operations.host_compute_free_memory
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-compute-memory-overhead"
    , {
        reqd= []
      ; optn= []
      ; help= "Computes the virtualization memory overhead of a host."
      ; implementation= No_fd Cli_operations.host_compute_memory_overhead
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-get-system-status-capabilities"
    , {
        reqd= []
      ; optn= []
      ; help= ""
      ; implementation=
          No_fd_local_session Cli_operations.host_get_system_status_capabilities
      ; flags= [Neverforward; Host_selectors]
      }
    )
  ; ( "host-get-system-status"
    , {
        reqd= ["filename"]
      ; optn= ["entries"; "output"]
      ; help=
          "Download system status into <filename>.  Entries is a \
           comma-separated list.  Output may be 'tar', 'tar.bz2' (the default) \
           or 'zip'."
      ; implementation= With_fd Cli_operations.host_get_system_status
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-set-hostname-live"
    , {
        reqd= ["host-uuid"; "host-name"]
      ; optn= []
      ; help=
          "Sets the host name to the specified string.  Both the API and \
           lower-level system hostname are changed."
      ; implementation= No_fd Cli_operations.host_set_hostname_live
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-set-power-on-mode"
    , {
        reqd= ["power-on-mode"]
      ; optn= ["power-on-config"]
      ; help= "Sets the power-on mode for the XE host"
      ; implementation= No_fd Cli_operations.host_set_power_on_mode
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-call-plugin"
    , {
        reqd= ["host-uuid"; "plugin"; "fn"]
      ; optn= ["args:"]
      ; help=
          "Calls the function within the plugin on the given host with \
           optional arguments. The syntax args:key:file=/path/file.ext passes \
           the content of /path/file.ext under key to the plugin."
      ; implementation= With_fd Cli_operations.host_call_plugin
      ; flags= []
      }
    )
  ; ( "host-retrieve-wlb-evacuate-recommendations"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Retrieves recommended host migrations to perform when evacuating \
           the host from the wlb server. If a vm cannot be migrated from the \
           host the reason is listed instead of a recommendation."
      ; implementation=
          No_fd Cli_operations.host_retrieve_wlb_evacuate_recommendations
      ; flags= [Hidden]
      }
    )
  ; ( "host-enable-external-auth"
    , {
        reqd= ["host-uuid"; "auth-type"; "service-name"]
      ; optn= ["config:"]
      ; help= "Enables external authentication in a host"
      ; implementation= No_fd Cli_operations.host_enable_external_auth
      ; flags= [Hidden]
      }
    )
  ; ( "host-disable-external-auth"
    , {
        reqd= ["host-uuid"]
      ; optn= ["config:"]
      ; help= "Disables external authentication in a host"
      ; implementation= No_fd Cli_operations.host_disable_external_auth
      ; flags= [Hidden]
      }
    )
  ; ( "host-refresh-pack-info"
    , {
        reqd= ["host-uuid"]
      ; optn= []
      ; help= "Refreshes Host.software_version"
      ; implementation= No_fd Cli_operations.host_refresh_pack_info
      ; flags= [Hidden]
      }
    )
  ; ( "host-cpu-info"
    , {
        reqd= []
      ; optn= ["uuid"]
      ; help= "Lists information about the host's physical CPUs."
      ; implementation= No_fd Cli_operations.host_cpu_info
      ; flags= []
      }
    )
  ; ( "host-get-cpu-features"
    , {
        reqd= []
      ; optn= ["uuid"]
      ; help=
          {|Prints a hexadecimal representation of the host's physical-CPU
           features for PV and HVM VMs. features_{hvm,pv} are "maximum"
           featuresets the host will accept during migrations, and
           features_{hvm,pv}_host will be used to start new VMs.|}
      ; implementation= No_fd Cli_operations.host_get_cpu_features
      ; flags= []
      }
    )
  ; ( "host-enable-display"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Enable display for the host"
      ; implementation= No_fd Cli_operations.host_enable_display
      ; flags= []
      }
    )
  ; ( "host-disable-display"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Disable display for the host"
      ; implementation= No_fd Cli_operations.host_disable_display
      ; flags= []
      }
    )
  ; ( "host-apply-updates"
    , {
        reqd= ["hash"]
      ; optn= []
      ; help= "Apply updates from enabled repository on specified host."
      ; implementation= No_fd Cli_operations.host_apply_updates
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-enable-ssh"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Enable SSH access on the host. It will start the service sshd only \
           if it is not running. It will also enable the service sshd only if \
           it is not enabled. A newly joined host in the pool or an ejected \
           host from the pool would keep the original status."
      ; implementation= No_fd Cli_operations.host_enable_ssh
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-disable-ssh"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Disable SSH access on the host. It will stop the service sshd only \
           if it is running. It will also disable the service sshd only if it \
           is enabled. A newly joined host in the pool or an ejected host from \
           the pool would keep the original status."
      ; implementation= No_fd Cli_operations.host_disable_ssh
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-emergency-clear-mandatory-guidance"
    , {
        reqd= []
      ; optn= []
      ; help= "Clear the pending mandatory guidance on this host"
      ; implementation=
          No_fd_local_session
            Cli_operations.host_emergency_clear_mandatory_guidance
      ; flags= [Neverforward]
      }
    )
  ; ( "patch-upload"
    , {
        reqd= ["file-name"]
      ; optn= []
      ; help= "Upload a patch file to the server."
      ; implementation= With_fd Cli_operations.patch_upload
      ; flags= []
      }
    )
  ; ( "patch-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Remove an unapplied patch record and files from the server."
      ; implementation= No_fd Cli_operations.patch_destroy
      ; flags= []
      }
    )
  ; ( "update-upload"
    , {
        reqd= ["file-name"]
      ; optn= ["sr-uuid"]
      ; help=
          "Stream new update to the server. The update will be uploaded to the \
           SR <sr-uuid>, or, if it is not specified, to the pool's default SR."
      ; implementation= With_fd Cli_operations.update_upload
      ; flags= []
      }
    )
  ; ( "patch-precheck"
    , {
        reqd= ["uuid"; "host-uuid"]
      ; optn= []
      ; help=
          "Run the prechecks contained within the patch previously uploaded to \
           the specified host."
      ; implementation= No_fd Cli_operations.patch_precheck
      ; flags= []
      }
    )
  ; ( "patch-apply"
    , {
        reqd= ["uuid"; "host-uuid"]
      ; optn= []
      ; help= "Apply the previously uploaded patch to the specified host."
      ; implementation= No_fd Cli_operations.patch_apply
      ; flags= []
      }
    )
  ; ( "patch-pool-apply"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Apply the previously uploaded patch to all hosts in the pool."
      ; implementation= No_fd Cli_operations.patch_pool_apply
      ; flags= []
      }
    )
  ; ( "patch-clean"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Delete a previously uploaded patch file."
      ; implementation= No_fd Cli_operations.patch_clean
      ; flags= []
      }
    )
  ; ( "patch-pool-clean"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Delete a previously uploaded patch file on all hosts in the pool."
      ; implementation= No_fd Cli_operations.patch_pool_clean
      ; flags= []
      }
    )
  ; ( "update-introduce"
    , {
        reqd= ["vdi-uuid"]
      ; optn= []
      ; help= "Introduce update VDI."
      ; implementation= No_fd Cli_operations.update_introduce
      ; flags= []
      }
    )
  ; ( "update-precheck"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Execute the precheck stage of the selected update on the specified \
           host."
      ; implementation= No_fd Cli_operations.update_precheck
      ; flags= [Host_selectors]
      }
    )
  ; ( "update-apply"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Apply the selected update to the specified host."
      ; implementation= No_fd Cli_operations.update_apply
      ; flags= [Host_selectors]
      }
    )
  ; ( "update-pool-apply"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Apply the selected update to all hosts in the pool."
      ; implementation= No_fd Cli_operations.update_pool_apply
      ; flags= []
      }
    )
  ; ( "update-pool-clean"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Removes the update's files from all hosts in the pool."
      ; implementation= No_fd Cli_operations.update_pool_clean
      ; flags= []
      }
    )
  ; ( "update-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Removes the database entry. Only works on unapplied update."
      ; implementation= No_fd Cli_operations.update_destroy
      ; flags= []
      }
    )
  ; ( "update-resync-host"
    , {
        reqd= ["host-uuid"]
      ; optn= []
      ; help= "Refreshes Host.updates"
      ; implementation= No_fd Cli_operations.update_resync_host
      ; flags= [Hidden]
      }
    )
  ; ( "user-password-change"
    , {
        reqd= ["new"]
      ; optn= ["old"]
      ; help= "Change a user's login password."
      ; implementation= No_fd Cli_operations.user_password_change
      ; flags= []
      }
    )
  ; ( "vm-compute-memory-overhead"
    , {
        reqd= []
      ; optn= []
      ; help= "Computes the virtualization memory overhead of a VM."
      ; implementation= No_fd Cli_operations.vm_compute_memory_overhead
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-memory-balloon"
    , {
        reqd= ["target"]
      ; optn= []
      ; help=
          "Set the memory target for a running VM. The given value must be \
           within the "
          ^ "range defined by the VM's memory_dynamic_min and \
             memory_dynamic_max values."
      ; implementation= No_fd Cli_operations.vm_memory_target_set
      ; flags=
          [Deprecated ["vm-memory-dynamic-range-set"]; Vm_selectors; Hidden]
      }
    )
  ; ( "vm-memory-dynamic-range-set"
    , {
        reqd= ["min"; "max"]
      ; optn= []
      ; help=
          "Configure the dynamic memory range of a VM. The dynamic memory \
           range defines soft lower and upper limits for a VM's memory. It's \
           possible to change these fields when a VM is running or halted. The \
           dynamic range must fit within the static range."
      ; implementation= No_fd Cli_operations.vm_memory_dynamic_range_set
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-memory-static-range-set"
    , {
        reqd= ["min"; "max"]
      ; optn= []
      ; help=
          "Configure the static memory range of a VM. The static memory range \
           defines hard lower and upper limits for a VM's memory. It's \
           possible to change these fields only when a VM is halted. The \
           static range must encompass the dynamic range."
      ; implementation= No_fd Cli_operations.vm_memory_static_range_set
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-memory-limits-set"
    , {
        reqd= ["static-min"; "static-max"; "dynamic-min"; "dynamic-max"]
      ; optn= []
      ; help= "Configure the memory limits of a VM."
      ; implementation= No_fd Cli_operations.vm_memory_limits_set
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-memory-set"
    , {
        reqd= ["memory"]
      ; optn= []
      ; help= "Configure the memory allocation of a VM."
      ; implementation= No_fd Cli_operations.vm_memory_set
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-memory-target-set"
    , {
        reqd= ["target"]
      ; optn= []
      ; help=
          "Set the memory target for a halted or running VM. The given value \
           must be within the range defined by the VM's memory_static_min and \
           memory_static_max values."
      ; implementation= No_fd Cli_operations.vm_memory_target_set
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-memory-target-wait"
    , {
        reqd= []
      ; optn= []
      ; help= "Wait for a running VM to reach its current memory target."
      ; implementation= No_fd Cli_operations.vm_memory_target_wait
      ; flags= [Vm_selectors; Hidden]
      }
    )
  ; ( "vm-data-source-list"
    , {
        reqd= []
      ; optn= []
      ; help= "List the data sources that can be recorded for a VM."
      ; implementation= No_fd Cli_operations.vm_data_source_list
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-data-source-record"
    , {
        reqd= ["data-source"]
      ; optn= []
      ; help= "Record the specified data source for a VM."
      ; implementation= No_fd Cli_operations.vm_data_source_record
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-data-source-query"
    , {
        reqd= ["data-source"]
      ; optn= []
      ; help= "Query the last value read from a VM data source."
      ; implementation= No_fd Cli_operations.vm_data_source_query
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-data-source-forget"
    , {
        reqd= ["data-source"]
      ; optn= []
      ; help=
          "Stop recording the specified data source for a VM, and forget all \
           of the recorded data."
      ; implementation= No_fd Cli_operations.vm_data_source_forget
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-memory-shadow-multiplier-set"
    , {
        reqd= ["multiplier"]
      ; optn= []
      ; help= "Set the shadow memory multiplier of a VM which may be running."
      ; implementation= No_fd Cli_operations.vm_memory_shadow_multiplier_set
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-clone"
    , {
        reqd= ["new-name-label"]
      ; optn= ["new-name-description"]
      ; help=
          "Clone an existing VM, using storage-level fast disk clone operation \
           where available."
      ; implementation= No_fd Cli_operations.vm_clone
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-snapshot"
    , {
        reqd= ["new-name-label"]
      ; optn= ["new-name-description"; "ignore-vdi-uuids"]
      ; help=
          "Snapshot an existing VM, using storage-level fast disk snapshot \
           operation where available."
      ; implementation= No_fd Cli_operations.vm_snapshot
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-snapshot-with-quiesce"
    , {
        reqd= ["new-name-label"]
      ; optn= ["new-name-description"]
      ; help=
          "Support for VSS has been removed - calling this will throw an \
           error. Snapshot an existing VM with quiesce, using storage-level \
           fast disk snapshot operation where available."
      ; implementation= No_fd Cli_operations.vm_snapshot_with_quiesce
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-checkpoint"
    , {
        reqd= ["new-name-label"]
      ; optn= ["new-name-description"]
      ; help=
          "Checkpoint an existing VM, using storage-level fast disk snapshot \
           operation where available."
      ; implementation= No_fd Cli_operations.vm_checkpoint
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-copy"
    , {
        reqd= ["new-name-label"]
      ; optn= ["new-name-description"; "sr-uuid"]
      ; help=
          "Copy an existing VM, but without using storage-level fast disk \
           clone operation (even if this is available). The disk images of the \
           copied VM are guaranteed to be 'full images' - i.e. not part of a \
           CoW chain."
      ; implementation= No_fd Cli_operations.vm_copy
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "snapshot-revert"
    , {
        reqd= []
      ; optn= ["uuid"; "snapshot-uuid"]
      ; help=
          "Revert an existing VM to a previous checkpointed or snapshotted \
           state."
      ; implementation= No_fd Cli_operations.snapshot_revert
      ; flags= [Standard]
      }
    )
  ; ( "vm-install"
    , {
        reqd= ["new-name-label"]
      ; optn= ["sr-name-label"; "sr-uuid"; "template"; "copy-bios-strings-from"]
      ; help=
          "Install a new VM from a template. The template parameter can match \
           either the template name or the uuid."
      ; implementation= No_fd Cli_operations.vm_install
      ; flags= [Standard]
      }
    )
  ; ( "vm-uninstall"
    , {
        reqd= []
      ; optn= ["force"]
      ; help=
          "Uninstall a VM. This operation will destroy those VDIs that are \
           marked RW and connected to this VM only. To simply destroy the VM \
           record, use vm-destroy."
      ; implementation= With_fd Cli_operations.vm_uninstall
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "console"
    , {
        reqd= []
      ; optn= []
      ; help= "Attach to a particular console."
      ; implementation= With_fd Cli_operations.console
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-query-services"
    , {
        reqd= []
      ; optn= []
      ; help= "Query the system services offered by the given VM(s)."
      ; implementation= No_fd Cli_operations.vm_query_services
      ; flags= [Standard; Vm_selectors; Hidden]
      }
    )
  ; ( "vm-start"
    , {
        reqd= []
      ; optn= ["force"; "on"; "paused"]
      ; help=
          "Start the selected VM(s). Where pooling is enabled, the host on \
           which to start can be specified with the 'on' parameter that takes \
           a uuid. The optional parameter '--force' will bypass any \
           hardware-compatibility warnings."
      ; implementation= No_fd Cli_operations.vm_start
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-suspend"
    , {
        reqd= []
      ; optn= []
      ; help= "Suspend the selected VM(s)."
      ; implementation= No_fd Cli_operations.vm_suspend
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-resume"
    , {
        reqd= []
      ; optn= ["force"; "on"]
      ; help= "Resume the selected VM(s)."
      ; implementation= No_fd Cli_operations.vm_resume
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-shutdown"
    , {
        reqd= []
      ; optn= ["force"]
      ; help=
          "Shutdown the selected VM(s). The optional argument --force will \
           forcibly shut down the VM."
      ; implementation= No_fd Cli_operations.vm_shutdown
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-reset-powerstate"
    , {
        reqd= []
      ; optn= ["force"]
      ; help=
          "Force the VM powerstate to halted in the management toolstack \
           database only. This command is used to recover a VM that is marked \
           as 'running', but is known to be on a dead slave host that will not \
           recover. This is a potentially dangerous operation: you must ensure \
           that the VM you are forcing to 'halted' is definitely not running \
           anywhere."
      ; implementation= No_fd Cli_operations.vm_reset_powerstate
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "snapshot-reset-powerstate"
    , {
        reqd= []
      ; optn= ["uuid"; "snapshot-uuid"; "force"]
      ; help=
          "Force the VM powerstate to halted in the management toolstack \
           database only. This command is used to recover a snapshot that is \
           marked as 'suspended'. This is a potentially dangerous operation: \
           you must ensure that you do not need the memory image anymore (ie. \
           you will not be able to resume your snapshot anymore)."
      ; implementation= No_fd Cli_operations.snapshot_reset_powerstate
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-reboot"
    , {
        reqd= []
      ; optn= ["force"]
      ; help= "Reboot the selected VM(s)."
      ; implementation= No_fd Cli_operations.vm_reboot
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-compute-maximum-memory"
    , {
        reqd= ["total"]
      ; optn= ["approximate"]
      ; help=
          "Compute the maximum amount of guest memory given the VM's \
           configuration. By default give a precise limit, if approximate is \
           set then allow some extra wiggle-room."
      ; implementation= No_fd Cli_operations.vm_compute_maximum_memory
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-retrieve-wlb-recommendations"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Retrieve the workload balancing recommendations for the selected VM."
      ; implementation= No_fd Cli_operations.vm_retrieve_wlb_recommendations
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-migrate"
    , {
        reqd= []
      ; optn=
          [
            "live"
          ; "host"
          ; "host-uuid"
          ; "remote-master"
          ; "remote-username"
          ; "remote-password"
          ; "remote-network"
          ; "force"
          ; "copy"
          ; "compress"
          ; "vif:"
          ; "vdi:"
          ]
      ; help=
          "Migrate the selected VM(s). The parameter '--live' will migrate the \
           VM without shutting it down. The 'host' parameter matches can be \
           either the name or the uuid of the host. If you are migrating a VM \
           to a remote pool, you will need to specify the remote-master, \
           remote-username, and remote-password parameters. remote-master is \
           the network address of the master host. To migrate to a particular \
           host within a remote pool, you may additionally specify the host or \
           host-uuid parameters. Also for cross-pool migration, setting \
           'copy=true' will enable the copy mode so that a stopped vm can be \
           copied, instead of migrating, to the destination pool. The vif and \
           vdi mapping parameters take the form 'vif:<source vif uuid>=<dest \
           network uuid>' and 'vdi:<source vdi uuid>=<dest sr uuid>'. \
           Unfortunately, destination uuids cannot be tab-completed."
      ; implementation= No_fd Cli_operations.vm_migrate
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-restart-device-models"
    , {
        reqd= []
      ; optn= []
      ; help= "Restart device models of a VM."
      ; implementation= No_fd Cli_operations.vm_restart_device_models
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-pause"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Pause a running VM. Note this operation does not free the \
           associated memory (see 'vm-suspend')."
      ; implementation= No_fd Cli_operations.vm_pause
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-unpause"
    , {
        reqd= []
      ; optn= []
      ; help= "Unpause a paused VM."
      ; implementation= No_fd Cli_operations.vm_unpause
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-disk-list"
    , {
        reqd= []
      ; optn= ["vbd-params"; "vdi-params"]
      ; help= "List the disks on the selected VM(s)."
      ; implementation= No_fd (Cli_operations.vm_disk_list false)
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-crashdump-list"
    , {
        reqd= []
      ; optn= []
      ; help= "List crashdumps associated with the selected VM(s)."
      ; implementation= No_fd Cli_operations.vm_crashdump_list
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-cd-add"
    , {
        reqd= ["cd-name"; "device"]
      ; optn= []
      ; help=
          "Add a CD to the VM(s). The device field should be selected from the \
           parameter 'allowed-VBD-devices' of the VM."
      ; implementation= No_fd Cli_operations.vm_cd_add
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-cd-list"
    , {
        reqd= []
      ; optn= ["vbd-params"; "vdi-params"]
      ; help= "List the CDs currently attached to the VM(s)."
      ; implementation= No_fd (Cli_operations.vm_disk_list true)
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-cd-remove"
    , {
        optn= []
      ; reqd= ["cd-name"]
      ; help= "Remove the selected CDs from the VM(s)."
      ; implementation= No_fd Cli_operations.vm_cd_remove
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-cd-eject"
    , {
        optn= []
      ; reqd= []
      ; help=
          "Eject a CD from the virtual CD drive. This command will only work \
           if there is one and only one CD attached to the VM. When there are \
           two or more CDs, please use the command 'vbd-eject' and specify the \
           uuid of the VBD."
      ; implementation= No_fd Cli_operations.vm_cd_eject
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-cd-insert"
    , {
        optn= []
      ; reqd= ["cd-name"]
      ; help=
          "Insert a CD into the virtual CD drive. This command will only work \
           if there is one and only one empty CD device attached to the VM. \
           When there are two or more empty CD devices, please use the command \
           'vbd-insert' and specify the uuids of the VBD and of the VDI to \
           insert."
      ; implementation= No_fd Cli_operations.vm_cd_insert
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-vcpu-hotplug"
    , {
        reqd= ["new-vcpus"]
      ; optn= []
      ; help= "Dynamically adjust the number of VCPUs available to running VM."
      ; implementation= No_fd Cli_operations.vm_vcpu_hotplug
      ; flags= [Vm_selectors]
      }
    )
  ; ( "cd-list"
    , {
        reqd= []
      ; optn= ["params"]
      ; help= "List the CDs available to be attached to VMs."
      ; implementation= No_fd Cli_operations.cd_list
      ; flags= [Standard]
      }
    )
  ; ( "vm-disk-add"
    , {
        reqd= ["disk-size"; "device"]
      ; optn= ["sr-uuid"]
      ; help=
          "Add a new disk to the selected VM(s). The device field should be \
           selected from the field 'allowed-VBD-devices' of the VM."
      ; implementation= No_fd Cli_operations.vm_disk_add
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-disk-remove"
    , {
        reqd= ["device"]
      ; optn= []
      ; help= "Remove a disk from the selected VM and destroy it."
      ; implementation= No_fd Cli_operations.vm_disk_remove
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-import"
    , {
        reqd= []
      ; optn=
          [
            "filename"
          ; "preserve"
          ; "sr-uuid"
          ; "force"
          ; "host-username"
          ; "host-password"
          ; "type"
          ; "remote-config"
          ; "dry-run"
          ; "metadata"
          ; "url"
          ; "vdi:"
          ]
      ; help=
          "Import a VM. If type=ESXServer is given, it will import from a \
           VMWare server and 'host-username', 'host-password' and \
           'remote-config' are required. Otherwise, it will import from a \
           file, and 'filename' is required. If the option preserve=true is \
           given then as many settings as possible are restored, including VIF \
           MAC addresses. The default is to regenerate VIF MAC addresses. The \
           VDIs will be imported into the Pool's default SR unless an override \
           is provided. If the force option is given then any disk data \
           checksum failures will be ignored. If the parameter 'url' is \
           specified, xapi will attempt to import from that URL. Only metadata \
           will be imported if 'metadata' is true"
      ; implementation= With_fd Cli_operations.vm_import
      ; flags= [Standard]
      }
    )
  ; ( "vm-export"
    , {
        reqd= ["filename"]
      ; optn=
          [
            "preserve-power-state"
          ; "compress"
          ; "metadata"
          ; "excluded-device-types"
          ; "include-snapshots"
          ]
      ; help= "Export a VM to <filename>."
      ; implementation= With_fd Cli_operations.vm_export
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vm-copy-bios-strings"
    , {
        reqd= ["host-uuid"]
      ; optn= []
      ; help= "Copy the BIOS strings of the given host to the VM."
      ; implementation= No_fd Cli_operations.vm_copy_bios_strings
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-is-bios-customized"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Indicates whether the BIOS strings of the VM have been customized."
      ; implementation= No_fd Cli_operations.vm_is_bios_customized
      ; flags= [Vm_selectors]
      }
    )
  ; ( "vm-call-plugin"
    , {
        reqd= ["vm-uuid"; "plugin"; "fn"]
      ; optn= ["args:"]
      ; help=
          "Calls the function within the plugin on the given vm with optional \
           arguments (args:key=value). To pass a \"value\" string with special \
           characters in it (e.g. new line), an alternative syntax \
           args:key:file=local_file can be used in place, where the content of \
           local_file will be retrieved and assigned to \"key\" as a whole."
      ; implementation= With_fd Cli_operations.vm_call_plugin
      ; flags= []
      }
    )
  ; ( "vm-call-host-plugin"
    , {
        reqd= ["vm-uuid"; "plugin"; "fn"]
      ; optn= ["args:"]
      ; help=
          "Calls function fn within the plugin on the host where the VM is \
           running with arguments (args:key=value). To pass a \"value\" string \
           with special characters in it (e.g. new line), an alternative \
           syntax args:key:file=local_file can be used in place, where the \
           content of local_file will be retrieved and assigned to \"key\" as \
           a whole."
      ; implementation= With_fd Cli_operations.vm_call_host_plugin
      ; flags= []
      }
    )
  ; ( "snapshot-export-to-template"
    , {
        reqd= ["filename"; "snapshot-uuid"]
      ; optn=
          [
            "preserve-power-state"
          ; "compress"
          ; "metadata"
          ; "excluded-device-types"
          ]
      ; help= "Export a snapshot to <filename>."
      ; implementation= With_fd Cli_operations.snapshot_export
      ; flags= [Standard]
      }
    )
  ; ( "snapshot-clone"
    , {
        reqd= ["new-name-label"]
      ; optn= ["uuid"; "new-name-description"]
      ; help=
          "Create a new template by cloning an existing snapshot, using \
           storage-level fast disk clone operation where available."
      ; implementation= No_fd Cli_operations.snapshot_clone
      ; flags= [Standard]
      }
    )
  ; ( "snapshot-copy"
    , {
        reqd= ["new-name-label"]
      ; optn= ["uuid"; "new-name-description"; "sr-uuid"]
      ; help=
          "Create a new template by copying an existing VM, but without using \
           storage-level fast disk clone operation (even if this is \
           available). The disk images of the copied VM are guaranteed to be \
           'full images' - i.e. not part of a CoW chain."
      ; implementation= No_fd Cli_operations.snapshot_copy
      ; flags= [Standard]
      }
    )
  ; ( "snapshot-uninstall"
    , {
        reqd= []
      ; optn= ["uuid"; "snapshot-uuid"; "force"]
      ; help=
          "Uninstall a snapshot. This operation will destroy those VDIs that \
           are marked RW and connected to this snapshot only. To simply \
           destroy the VM record, use snapshot-destroy."
      ; implementation= With_fd Cli_operations.snapshot_uninstall
      ; flags= [Standard]
      }
    )
  ; ( "snapshot-destroy"
    , {
        reqd= []
      ; optn= ["uuid"; "snapshot-uuid"]
      ; help=
          "Destroy a snapshot. This leaves the storage associated with the \
           snapshot intact. To delete storage too, use snapshot-uninstall."
      ; implementation= No_fd Cli_operations.snapshot_destroy
      ; flags= []
      }
    )
  ; ( "snapshot-disk-list"
    , {
        reqd= []
      ; optn= ["uuid"; "snapshot-uuid"; "vbd-params"; "vdi-params"]
      ; help= "List the disks on the selected VM(s)."
      ; implementation= No_fd (Cli_operations.snapshot_disk_list false)
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "template-export"
    , {
        reqd= ["filename"; "template-uuid"]
      ; optn= ["compress"; "metadata"; "excluded-device-types"]
      ; help= "Export a template to <filename>."
      ; implementation= With_fd Cli_operations.template_export
      ; flags= [Standard]
      }
    )
  ; ( "template-uninstall"
    , {
        reqd= ["template-uuid"]
      ; optn= ["force"]
      ; help=
          "Uninstall a custom template. This operation will destroy those VDIs \
           that are marked as 'owned' by this template"
      ; implementation= With_fd Cli_operations.template_uninstall
      ; flags= [Standard]
      }
    )
  ; ( "vm-vif-list"
    , {
        reqd= []
      ; optn= []
      ; help= "List the VIFs present on selected VM."
      ; implementation= No_fd Cli_operations.vm_vif_list
      ; flags= [Standard; Vm_selectors]
      }
    )
  ; ( "vlan-create"
    , {
        reqd= ["pif-uuid"; "vlan"; "network-uuid"]
      ; optn= []
      ; help= "Create a new VLAN on a host."
      ; implementation= No_fd Cli_operations.vlan_create
      ; flags= []
      }
    )
  ; ( "vlan-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a VLAN."
      ; implementation= No_fd Cli_operations.vlan_destroy
      ; flags= []
      }
    )
  ; ( "tunnel-create"
    , {
        reqd= ["pif-uuid"; "network-uuid"]
      ; optn= ["protocol"]
      ; help= "Create a new tunnel on a host."
      ; implementation= No_fd Cli_operations.tunnel_create
      ; flags= []
      }
    )
  ; ( "tunnel-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a tunnel."
      ; implementation= No_fd Cli_operations.tunnel_destroy
      ; flags= []
      }
    )
  ; ( "network-sriov-create"
    , {
        reqd= ["pif-uuid"; "network-uuid"]
      ; optn= []
      ; help= "Create a new network-sriov on a PIF."
      ; implementation= No_fd Cli_operations.Network_sriov.create
      ; flags= []
      }
    )
  ; ( "network-sriov-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a network-sriov."
      ; implementation= No_fd Cli_operations.Network_sriov.destroy
      ; flags= []
      }
    )
  ; ( "pif-unplug"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Attempt to bring down a network interface."
      ; implementation= No_fd Cli_operations.pif_unplug
      ; flags= []
      }
    )
  ; ( "pif-plug"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Attempt to bring up a network interface."
      ; implementation= No_fd Cli_operations.pif_plug
      ; flags= []
      }
    )
  ; ( "pif-reconfigure-ip"
    , {
        reqd= ["uuid"; "mode"]
      ; optn= ["IP"; "netmask"; "gateway"; "DNS"]
      ; help= "Reconfigure the IP address settings on a PIF."
      ; implementation= No_fd Cli_operations.pif_reconfigure_ip
      ; flags= []
      }
    )
  ; ( "pif-reconfigure-ipv6"
    , {
        reqd= ["uuid"; "mode"]
      ; optn= ["IPv6"; "gateway"; "DNS"]
      ; help= "Reconfigure the IPv6 address settings on a PIF."
      ; implementation= No_fd Cli_operations.pif_reconfigure_ipv6
      ; flags= []
      }
    )
  ; ( "pif-set-primary-address-type"
    , {
        reqd= ["uuid"; "primary_address_type"]
      ; optn= []
      ; help= "Change the primary address type used by this PIF."
      ; implementation= No_fd Cli_operations.pif_set_primary_address_type
      ; flags= []
      }
    )
  ; ( "pif-scan"
    , {
        reqd= ["host-uuid"]
      ; optn= []
      ; help= "Scan for new physical interfaces on a host."
      ; implementation= No_fd Cli_operations.pif_scan
      ; flags= []
      }
    )
  ; ( "pif-introduce"
    , {
        reqd= ["host-uuid"; "device"]
      ; optn= ["mac"; "managed"]
      ; help=
          "Create a new PIF object representing a physical interface on a host."
      ; implementation= No_fd Cli_operations.pif_introduce
      ; flags= []
      }
    )
  ; ( "pif-forget"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a PIF object on a particular host."
      ; implementation= No_fd Cli_operations.pif_forget
      ; flags= []
      }
    )
  ; ( "pif-db-forget"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Destroy the database object representing a PIF on a particular host."
      ; implementation= No_fd Cli_operations.pif_db_forget
      ; flags= [Hidden]
      }
    )
  ; ( "bond-create"
    , {
        reqd= ["network-uuid"; "pif-uuids"]
      ; optn= ["mac"; "mode"; "properties:"]
      ; help= "Create a bonded interface from a list of existing PIF objects."
      ; implementation= No_fd Cli_operations.bond_create
      ; flags= []
      }
    )
  ; ( "bond-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a bonded interface."
      ; implementation= No_fd Cli_operations.bond_destroy
      ; flags= []
      }
    )
  ; ( "bond-set-mode"
    , {
        reqd= ["uuid"; "mode"]
      ; optn= []
      ; help= "Change the bond mode."
      ; implementation= No_fd Cli_operations.bond_set_mode
      ; flags= []
      }
    )
  ; (* Lowlevel non-autogenerated stuff *)
    ( "vbd-create"
    , {
        reqd= ["vm-uuid"; "device"]
      ; optn= ["vdi-uuid"; "bootable"; "type"; "mode"; "unpluggable"]
      ; help=
          "Create a VBD. Appropriate values for the device field are listed in \
           the parameter 'allowed-VBD-devices' on the VM. If no VDI is \
           specified, an empty VBD will be created. The type parameter can be \
           'Disk' or 'CD', and the mode is 'RO' or 'RW'."
      ; implementation= No_fd Cli_operations.vbd_create
      ; flags= []
      }
    )
  ; ( "vbd-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a VBD."
      ; implementation= No_fd Cli_operations.vbd_destroy
      ; flags= []
      }
    )
  ; ( "vbd-insert"
    , {
        reqd= ["uuid"; "vdi-uuid"]
      ; optn= []
      ; help= "Insert new media into the drive represented by a VBD."
      ; implementation= No_fd Cli_operations.vbd_insert
      ; flags= []
      }
    )
  ; ( "vbd-eject"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Remove the media from the drive represented by a VBD."
      ; implementation= No_fd Cli_operations.vbd_eject
      ; flags= []
      }
    )
  ; ( "vbd-plug"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Attempt to attach the VBD while the VM is in the running state."
      ; implementation= No_fd Cli_operations.vbd_plug
      ; flags= []
      }
    )
  ; ( "vbd-unplug"
    , {
        reqd= ["uuid"]
      ; optn= ["timeout"; "force"]
      ; help=
          "Attempt to detach the VBD while the VM is in the running state. If \
           the optional argument 'timeout=N' is given then the command will \
           wait for up to 'N' seconds for the unplug to complete. If the \
           optional argument 'force' is given then it will be immediately \
           unplugged."
      ; implementation= No_fd Cli_operations.vbd_unplug
      ; flags= []
      }
    )
  ; ( "vbd-pause"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Request that a backend block device pauses itself."
      ; implementation= No_fd Cli_operations.vbd_pause
      ; flags= [Hidden]
      }
    )
  ; ( "vbd-unpause"
    , {
        reqd= ["uuid"; "token"]
      ; optn= []
      ; help= "Request that a backend block device unpauses itself."
      ; implementation= No_fd Cli_operations.vbd_unpause
      ; flags= [Hidden]
      }
    )
  ; ( "sr-create"
    , {
        reqd= ["name-label"; "type"]
      ; optn=
          [
            "host-uuid"
          ; "device-config:"
          ; "shared"
          ; "physical-size"
          ; "content-type"
          ; "sm-config:"
          ]
      ; help=
          "Create an SR, also a PBD. the device-config parameters can be \
           specified by e.g. device-config:foo=baa."
      ; implementation= With_fd Cli_operations.sr_create
      ; flags= []
      }
    )
  ; ( "sr-probe"
    , {
        reqd= ["type"]
      ; optn= ["host-uuid"; "device-config:"; "sm-config:"]
      ; help=
          "Perform a storage probe.  The device-config parameters can be \
           specified by e.g. device-config:devs=/dev/sdb1."
      ; implementation= No_fd Cli_operations.sr_probe
      ; flags= []
      }
    )
  ; ( "sr-probe-ext"
    , {
        reqd= ["type"]
      ; optn= ["host-uuid"; "device-config:"; "sm-config:"]
      ; help=
          "Perform a storage probe. The device-config parameters can be \
           specified by e.g. device-config:devs=/dev/sdb1. Unlike sr-probe, \
           this command returns results in the same human-readable format for \
           every SR type."
      ; implementation= No_fd Cli_operations.sr_probe_ext
      ; flags= []
      }
    )
  ; ( "sr-scan"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Force an SR scan, syncing database with VDIs present in underlying \
           storage substrate."
      ; implementation= No_fd Cli_operations.sr_scan
      ; flags= []
      }
    )
  ; ( "sr-introduce"
    , {
        reqd= ["name-label"; "type"; "uuid"]
      ; optn= ["shared"; "content-type"]
      ; help= "Introduces an SR (but does not create any PBDs)."
      ; implementation= No_fd Cli_operations.sr_introduce
      ; flags= []
      }
    )
  ; ( "sr-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy the SR."
      ; implementation= No_fd Cli_operations.sr_destroy
      ; flags= []
      }
    )
  ; ( "sr-forget"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Forget about the SR."
      ; implementation= No_fd Cli_operations.sr_forget
      ; flags= []
      }
    )
  ; ( "sr-update"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Refresh the fields of the SR object in the database."
      ; implementation= No_fd Cli_operations.sr_update
      ; flags= []
      }
    )
  ; ( "sr-enable-database-replication"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Enable database replication to the SR."
      ; implementation= No_fd Cli_operations.sr_enable_database_replication
      ; flags= []
      }
    )
  ; ( "sr-disable-database-replication"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Disable database replication to the SR."
      ; implementation= No_fd Cli_operations.sr_disable_database_replication
      ; flags= []
      }
    )
  ; ( "sr-data-source-list"
    , {
        reqd= []
      ; optn= []
      ; help= "List the data sources that can be recorded for a SR."
      ; implementation= No_fd Cli_operations.sr_data_source_list
      ; flags= [Sr_selectors]
      }
    )
  ; ( "sr-data-source-record"
    , {
        reqd= ["data-source"]
      ; optn= []
      ; help= "Record the specified data source for a SR."
      ; implementation= No_fd Cli_operations.sr_data_source_record
      ; flags= [Sr_selectors]
      }
    )
  ; ( "sr-data-source-query"
    , {
        reqd= ["data-source"]
      ; optn= []
      ; help= "Query the last value read from a SR data source."
      ; implementation= No_fd Cli_operations.sr_data_source_query
      ; flags= [Sr_selectors]
      }
    )
  ; ( "sr-data-source-forget"
    , {
        reqd= ["data-source"]
      ; optn= []
      ; help=
          "Stop recording the specified data source for a SR, and forget all \
           of the recorded data."
      ; implementation= No_fd Cli_operations.sr_data_source_forget
      ; flags= [Sr_selectors]
      }
    )
  ; ( "vdi-create"
    , {
        reqd= ["sr-uuid"; "name-label"; "virtual-size"]
      ; optn= ["sm-config:"; "sharable"; "tags:"; "type"]
      ; help= "Create a VDI. Type is 'system' 'user' 'suspend' or 'crashdump'."
      ; implementation= No_fd Cli_operations.vdi_create
      ; flags= []
      }
    )
  ; ( "vdi-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a VDI."
      ; implementation= No_fd Cli_operations.vdi_destroy
      ; flags= []
      }
    )
  ; ( "vdi-forget"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Forget about a VDI."
      ; implementation= No_fd Cli_operations.vdi_forget
      ; flags= []
      }
    )
  ; ( "vdi-update"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Refresh the fields of the VDI object in the database."
      ; implementation= No_fd Cli_operations.vdi_update
      ; flags= []
      }
    )
  ; ( "vdi-introduce"
    , {
        reqd= ["uuid"; "sr-uuid"; "type"; "location"]
      ; optn=
          [
            "name-description"
          ; "sharable"
          ; "read-only"
          ; "managed"
          ; "other-config:"
          ; "xenstore-data:"
          ; "sm-config:"
          ; "name-label"
          ]
      ; help= "Create a VDI object representing an existing disk."
      ; implementation= No_fd Cli_operations.vdi_introduce
      ; flags= []
      }
    )
  ; ( "vdi-import"
    , {
        reqd= ["uuid"; "filename"]
      ; optn= ["format"; "progress"]
      ; help= "Import a raw VDI."
      ; implementation= With_fd Cli_operations.vdi_import
      ; flags= []
      }
    )
  ; ( "vdi-export"
    , {
        reqd= ["uuid"; "filename"]
      ; optn= ["format"; "base"; "progress"]
      ; help= "Export a VDI."
      ; implementation= With_fd Cli_operations.vdi_export
      ; flags= []
      }
    )
  ; ( "vdi-resize"
    , {
        reqd= ["uuid"; "disk-size"]
      ; optn= ["online"]
      ; help= "Resize a VDI."
      ; implementation= No_fd Cli_operations.vdi_resize
      ; flags= []
      }
    )
  ; ( "vdi-generate-config"
    , {
        reqd= ["host-uuid"; "uuid"]
      ; optn= []
      ; help= "Generate a static VDI configuration."
      ; implementation= No_fd Cli_operations.vdi_generate_config
      ; flags= [Hidden]
      }
    )
  ; ( "vdi-copy"
    , {
        reqd= ["uuid"]
      ; optn= ["sr-uuid"; "base-vdi-uuid"; "into-vdi-uuid"]
      ; help=
          "Copy either a full VDI or the block differences between two VDIs \
           either into a fresh VDI in a specified SR or into an existing VDI."
      ; implementation= No_fd Cli_operations.vdi_copy
      ; flags= []
      }
    )
  ; ( "vdi-pool-migrate"
    , {
        reqd= ["uuid"; "sr-uuid"]
      ; optn= []
      ; help=
          "Migrate a VDI to a specified SR, while the VDI is attached to a \
           running guest."
      ; implementation= No_fd Cli_operations.vdi_pool_migrate
      ; flags= []
      }
    )
  ; ( "vdi-clone"
    , {
        reqd= ["uuid"]
      ; optn= ["driver-params-"; "new-name-label"; "new-name-description"]
      ; help= "Clone a specified VDI."
      ; implementation= No_fd Cli_operations.vdi_clone
      ; flags= []
      }
    )
  ; ( "vdi-snapshot"
    , {
        reqd= ["uuid"]
      ; optn= ["driver-params-"]
      ; help= "Snapshot a specified VDI."
      ; implementation= No_fd Cli_operations.vdi_snapshot
      ; flags= []
      }
    )
  ; ( "vdi-unlock"
    , {
        reqd= ["uuid"]
      ; optn= ["force"]
      ; help= "Attempt to unlock a VDI."
      ; implementation= No_fd Cli_operations.vdi_unlock
      ; flags= []
      }
    )
  ; ( "vdi-enable-cbt"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Enable changed block tracking on a VDI."
      ; implementation= No_fd Cli_operations.vdi_enable_cbt
      ; flags= []
      }
    )
  ; ( "vdi-disable-cbt"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Disable changed block tracking on a VDI."
      ; implementation= No_fd Cli_operations.vdi_disable_cbt
      ; flags= []
      }
    )
  ; ( "vdi-data-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Delete the data of the VDI, but keep its changed block tracking \
           metadata."
      ; implementation= No_fd Cli_operations.vdi_data_destroy
      ; flags= []
      }
    )
  ; ( "vdi-list-changed-blocks"
    , {
        reqd= ["vdi-from-uuid"; "vdi-to-uuid"]
      ; optn= []
      ; help=
          "Write the changed blocks between the two given VDIs to the standard \
           output as a base64-encoded bitmap string."
      ; implementation= With_fd Cli_operations.vdi_list_changed_blocks
      ; flags= []
      }
    )
  ; ( "diagnostic-vdi-status"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Query the locking and sharing status of a VDI."
      ; implementation= No_fd Cli_operations.diagnostic_vdi_status
      ; flags= []
      }
    )
  ; ( "pbd-create"
    , {
        reqd= ["host-uuid"; "sr-uuid"]
      ; optn= ["device-config:"]
      ; help=
          "Create a PBD. The read-only device-config parameter can only be set \
           on creation in the following manner. To\n\
           add a mapping of 'path' -> '/tmp', the command line should contain \
           the argument device-config:path=/tmp"
      ; implementation= No_fd Cli_operations.pbd_create
      ; flags= []
      }
    )
  ; ( "pbd-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy the PBD."
      ; implementation= No_fd Cli_operations.pbd_destroy
      ; flags= []
      }
    )
  ; ( "pbd-plug"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Attempt to plug in the PBD to the host. If this succeeds then the \
           referenced SR (and the VDIs contained within) should be visible to \
           the host."
      ; implementation= No_fd Cli_operations.pbd_plug
      ; flags= []
      }
    )
  ; ( "pbd-unplug"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Attempt to unplug the PBD from the host. If this succeeds then the \
           referenced SR (and the VDIs contained within) should not be visible \
           to the host."
      ; implementation= No_fd Cli_operations.pbd_unplug
      ; flags= []
      }
    )
  ; ( "network-create"
    , {
        reqd= ["name-label"]
      ; optn= ["name-description"; "MTU"; "bridge"; "managed"]
      ; help= "Create a new network."
      ; implementation= No_fd Cli_operations.net_create
      ; flags= []
      }
    )
  ; ( "network-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Delete an existing network."
      ; implementation= No_fd Cli_operations.net_destroy
      ; flags= []
      }
    )
  ; ( "network-attach"
    , {
        reqd= ["uuid"; "host-uuid"]
      ; optn= []
      ; help= "Make a network appear on a particular host."
      ; implementation= No_fd Cli_operations.net_attach
      ; flags= [Hidden]
      }
    )
  ; ( "vif-create"
    , {
        reqd= ["device"; "network-uuid"; "vm-uuid"]
      ; optn= ["mac"]
      ; help=
          "Create a VIF. Appropriate values for the device are listed in the \
           parameter 'allowed-VIF-devices' on the VM. If specified, the MAC \
           parameter is of the form aa:bb:cc:dd:ee:ff. If MAC is not specified \
           the server will choose an appropriate MAC automatically."
      ; implementation= No_fd Cli_operations.vif_create
      ; flags= []
      }
    )
  ; ( "vif-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a VIF."
      ; implementation= No_fd Cli_operations.vif_destroy
      ; flags= []
      }
    )
  ; ( "vif-plug"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Attempt to attach the VIF while the VM is in the running state."
      ; implementation= No_fd Cli_operations.vif_plug
      ; flags= []
      }
    )
  ; ( "vif-unplug"
    , {
        reqd= ["uuid"]
      ; optn= ["force"]
      ; help= "Attempt to detach the VIF while the VM is in the running state."
      ; implementation= No_fd Cli_operations.vif_unplug
      ; flags= []
      }
    )
  ; ( "vif-configure-ipv4"
    , {
        reqd= ["uuid"; "mode"]
      ; optn= ["address"; "gateway"]
      ; help= "Configure IPv4 settings on a VIF."
      ; implementation= No_fd Cli_operations.vif_configure_ipv4
      ; flags= []
      }
    )
  ; ( "vif-configure-ipv6"
    , {
        reqd= ["uuid"; "mode"]
      ; optn= ["address"; "gateway"]
      ; help= "Configure IPv6 settings on a VIF."
      ; implementation= No_fd Cli_operations.vif_configure_ipv6
      ; flags= []
      }
    )
  ; ( "vif-move"
    , {
        reqd= ["uuid"; "network-uuid"]
      ; optn= []
      ; help= "Move the VIF to another network."
      ; implementation= No_fd Cli_operations.vif_move
      ; flags= []
      }
    )
  ; ( "vm-create"
    , {
        reqd= ["name-label"]
      ; optn= ["name-description"]
      ; help= "Create a new VM with default parameters."
      ; implementation= No_fd Cli_operations.vm_create
      ; flags= [Hidden]
      }
    )
  ; ( "vm-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Destroy a VM. This leaves the storage associated with the VM \
           intact. To delete storage too, use vm-uninstall."
      ; implementation= No_fd Cli_operations.vm_destroy
      ; flags= []
      }
    )
  ; ( "vm-recover"
    , {
        reqd= ["uuid"]
      ; optn= ["database:"; "force"]
      ; help= "Recover a VM from the database contained in the supplied VDI."
      ; implementation= No_fd Cli_operations.vm_recover
      ; flags= []
      }
    )
  ; ( "vm-assert-can-be-recovered"
    , {
        reqd= ["uuid"]
      ; optn= ["database:"]
      ; help= "Test whether storage is available to recover this VM."
      ; implementation= No_fd Cli_operations.vm_assert_can_be_recovered
      ; flags= []
      }
    )
  ; ( "vm-set-uefi-mode"
    , {
        reqd= ["uuid"; "mode"]
      ; optn= []
      ; help= "Set a VM in UEFI 'setup' or 'user' mode."
      ; implementation= No_fd Cli_operations.vm_set_uefi_mode
      ; flags= []
      }
    )
  ; ( "vm-get-secureboot-readiness"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Return the secureboot readiness of the VM."
      ; implementation= No_fd Cli_operations.vm_get_secureboot_readiness
      ; flags= []
      }
    )
  ; ( "vm-group-create"
    , {
        reqd= ["name-label"; "placement"]
      ; optn= ["name-description"]
      ; help= "Create a VM group."
      ; implementation= No_fd Cli_operations.VM_group.create
      ; flags= []
      }
    )
  ; ( "vm-group-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a VM group."
      ; implementation= No_fd Cli_operations.VM_group.destroy
      ; flags= []
      }
    )
  ; ( "vm-sysprep"
    , {
        reqd= ["filename"]
      ; optn= ["timeout"]
      ; help= "Pass and execute sysprep configuration file"
      ; implementation= With_fd Cli_operations.vm_sysprep
      ; flags= [Vm_selectors]
      }
    )
  ; ( "diagnostic-vm-status"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Query the hosts on which the VM can boot, check the sharing/locking \
           status of all VBDs."
      ; implementation= No_fd Cli_operations.diagnostic_vm_status
      ; flags= [Standard]
      }
    )
  ; ( "diagnostic-license-status"
    , {
        reqd= []
      ; optn= []
      ; help= "Help diagnose pool-wide licensing problems."
      ; implementation= No_fd Cli_operations.diagnostic_license_status
      ; flags= []
      }
    )
  ; ( "event-wait"
    , {
        reqd= ["class"]
      ; optn= []
      ; help=
          "Wait for the event that satisfies the conditions given on the \
           command line."
      ; implementation= No_fd Cli_operations.event_wait
      ; flags= []
      }
    )
  ; ( "host-data-source-list"
    , {
        reqd= []
      ; optn= []
      ; help= "List the data sources that can be recorded for a Host."
      ; implementation= No_fd Cli_operations.host_data_source_list
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-data-source-record"
    , {
        reqd= ["data-source"]
      ; optn= []
      ; help= "Record the specified data source for a Host."
      ; implementation= No_fd Cli_operations.host_data_source_record
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-data-source-query"
    , {
        reqd= ["data-source"]
      ; optn= []
      ; help= "Query the last value read from a Host data source."
      ; implementation= No_fd Cli_operations.host_data_source_query
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-data-source-forget"
    , {
        reqd= ["data-source"]
      ; optn= []
      ; help=
          "Stop recording the specified data source for a Host, and forget all \
           of the recorded data."
      ; implementation= No_fd Cli_operations.host_data_source_forget
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-license-add"
    , {
        reqd= ["license-file"]
      ; optn= ["host-uuid"]
      ; help= "Add a license to a host."
      ; implementation= With_fd Cli_operations.host_license_add
      ; flags= []
      }
    )
  ; ( "host-license-remove"
    , {
        reqd= []
      ; optn= ["host-uuid"]
      ; help= "Remove any licensing applied to a host."
      ; implementation= No_fd Cli_operations.host_license_remove
      ; flags= []
      }
    )
  ; ( "host-license-view"
    , {
        reqd= []
      ; optn= ["host-uuid"]
      ; help= "View the license parameters of the host."
      ; implementation= No_fd Cli_operations.host_license_view
      ; flags= []
      }
    )
  ; ( "host-apply-edition"
    , {
        reqd= ["edition"]
      ; optn= ["host-uuid"; "license-server-address"; "license-server-port"]
      ; help=
          "Change to another edition, or reactivate the current edition after \
           a license has expired. This may be subject to the successful \
           checkout of an appropriate license."
      ; implementation= No_fd Cli_operations.host_apply_edition
      ; flags= []
      }
    )
  ; ( "host-all-editions"
    , {
        reqd= []
      ; optn= []
      ; help= "Get a list of all available editions."
      ; implementation= No_fd Cli_operations.host_all_editions
      ; flags= []
      }
    )
  ; ( "host-evacuate"
    , {
        reqd= []
      ; optn= ["network-uuid"; "batch-size"]
      ; help= "Migrate all VMs off a host."
      ; implementation= No_fd Cli_operations.host_evacuate
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-get-vms-which-prevent-evacuation"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Return a list of VMs which prevent the evacuation of a specific \
           host and display reasons for each one."
      ; implementation=
          No_fd Cli_operations.host_get_vms_which_prevent_evacuation
      ; flags= []
      }
    )
  ; ( "host-shutdown-agent"
    , {
        reqd= []
      ; optn= []
      ; help= "Shut down the agent on the local host."
      ; implementation= No_fd_local_session Cli_operations.host_shutdown_agent
      ; flags= [Neverforward]
      }
    )
  ; ( "diagnostic-compact"
    , {
        reqd= []
      ; optn= []
      ; help= "Perform a major GC collection and heap compaction."
      ; implementation= No_fd Cli_operations.diagnostic_compact
      ; flags= [Host_selectors]
      }
    )
  ; ( "diagnostic-gc-stats"
    , {
        reqd= []
      ; optn= []
      ; help= "Print GC stats."
      ; implementation= No_fd Cli_operations.diagnostic_gc_stats
      ; flags= [Host_selectors]
      }
    )
  ; ( "diagnostic-timing-stats"
    , {
        reqd= []
      ; optn= []
      ; help= "Print timing stats."
      ; implementation= No_fd Cli_operations.diagnostic_timing_stats
      ; flags= []
      }
    )
  ; ( "diagnostic-db-stats"
    , {
        reqd= []
      ; optn= []
      ; help= "Print db stats."
      ; implementation= No_fd Cli_operations.diagnostic_db_stats
      ; flags= []
      }
    )
  ; ( "diagnostic-net-stats"
    , {
        reqd= []
      ; optn= ["uri"; "method"; "params"]
      ; help= "Print network stats."
      ; implementation= No_fd Cli_operations.diagnostic_net_stats
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-get-sm-diagnostics"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Display per-host SM diagnostic information."
      ; implementation= No_fd Cli_operations.host_get_sm_diagnostics
      ; flags= []
      }
    )
  ; ( "host-get-thread-diagnostics"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Display per-host thread diagnostic information."
      ; implementation= No_fd Cli_operations.host_get_thread_diagnostics
      ; flags= []
      }
    )
  ; ( "host-sm-dp-destroy"
    , {
        reqd= ["uuid"; "dp"]
      ; optn= ["allow-leak"]
      ; help=
          "Attempt to destroy and clean up a storage datapath on a host. If \
           allow-leak=true is provided then it will delete all records of the \
           datapath even if it could not be shutdown cleanly."
      ; implementation= No_fd Cli_operations.host_sm_dp_destroy
      ; flags= []
      }
    )
  ; ( "task-cancel"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Set a task to cancelling and return."
      ; implementation= No_fd Cli_operations.task_cancel
      ; flags= []
      }
    )
  ; ( "pool-vlan-create"
    , {
        reqd= ["pif-uuid"; "vlan"; "network-uuid"]
      ; optn= []
      ; help= "Create a new VLAN on each host in a pool."
      ; implementation= No_fd Cli_operations.pool_vlan_create
      ; flags= []
      }
    )
  ; ( "pool-ha-enable"
    , {
        reqd= []
      ; optn= ["heartbeat-sr-uuids"; "ha-config:"]
      ; help= "Enable HA on this Pool."
      ; implementation= No_fd Cli_operations.pool_ha_enable
      ; flags= []
      }
    )
  ; ( "pool-ha-disable"
    , {
        reqd= []
      ; optn= []
      ; help= "Disable HA on this Pool."
      ; implementation= No_fd Cli_operations.pool_ha_disable
      ; flags= []
      }
    )
  ; ( "pool-ha-prevent-restarts-for"
    , {
        reqd= ["seconds"]
      ; optn= []
      ; help= "Prevent HA VM restarts for a given number of seconds"
      ; implementation= No_fd Cli_operations.pool_ha_prevent_restarts_for
      ; flags= [Hidden]
      }
    )
  ; ( "pool-ha-compute-max-host-failures-to-tolerate"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Compute the maximum number of host failures to tolerate under the \
           current Pool configuration"
      ; implementation=
          No_fd Cli_operations.pool_ha_compute_max_host_failures_to_tolerate
      ; flags= []
      }
    )
  ; ( "pool-ha-compute-hypothetical-max-host-failures-to-tolerate"
    , {
        reqd= []
      ; optn= ["vm-uuid"; "restart-priority"]
      ; (* multiple of these *)
        help=
          "Compute the maximum number of host failures to tolerate with the \
           supplied, proposed protected VMs."
      ; implementation=
          No_fd
            Cli_operations
            .pool_ha_compute_hypothetical_max_host_failures_to_tolerate
      ; flags= []
      }
    )
  ; ( "pool-ha-compute-vm-failover-plan"
    , {
        reqd= ["host-uuids"]
      ; optn= []
      ; help= "Compute a VM failover plan assuming the given set of hosts fail."
      ; implementation= No_fd Cli_operations.pool_ha_compute_vm_failover_plan
      ; flags= [Hidden]
      }
    )
  ; ( "pool-enable-redo-log"
    , {
        reqd= ["sr-uuid"]
      ; optn= []
      ; help=
          "Enable the redo log on the given SR and start using it, unless HA \
           is enabled."
      ; implementation= No_fd Cli_operations.pool_enable_redo_log
      ; flags= []
      }
    )
  ; ( "pool-disable-redo-log"
    , {
        reqd= []
      ; optn= []
      ; help= "Disable the redo log if in use, unless HA is enabled."
      ; implementation= No_fd Cli_operations.pool_disable_redo_log
      ; flags= []
      }
    )
  ; ( "pool-configure-update-sync"
    , {
        reqd= ["update-sync-frequency"; "update-sync-day"]
      ; optn= []
      ; help=
          "Configure periodic update synchronization from a remote CDN. \
           'update_sync_frequency': the frequency the synchronizations happen \
           from a remote CDN: daily or weekly. 'update_sync_day': which day of \
           the week the synchronizations will be scheduled in. For 'daily' \
           schedule, the value is ignored. For 'weekly' schedule, valid values \
           are 0 to 6, where 0 is Sunday."
      ; implementation= No_fd Cli_operations.pool_configure_update_sync
      ; flags= []
      }
    )
  ; ( "pool-set-update-sync-enabled"
    , {
        reqd= ["value"]
      ; optn= []
      ; help=
          "Enable or disable periodic update synchronization depending on the \
           value"
      ; implementation= No_fd Cli_operations.pool_set_update_sync_enabled
      ; flags= []
      }
    )
  ; ( "pool-sync-bundle"
    , {
        reqd= ["filename"]
      ; optn= []
      ; help=
          "Upload and unpack a bundle file, after that, sync the bundle \
           repository."
      ; implementation= With_fd Cli_operations.pool_sync_bundle
      ; flags= []
      }
    )
  ; ( "pool-enable-ssh"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Enable SSH access on all hosts in the pool. It's a helper which \
           calls host.enable_ssh for all the hosts in the pool."
      ; implementation= No_fd Cli_operations.pool_enable_ssh
      ; flags= []
      }
    )
  ; ( "pool-disable-ssh"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Disable SSH access on all hosts in the pool. It's a helper which \
           calls host.disable_ssh for all the hosts in the pool."
      ; implementation= No_fd Cli_operations.pool_disable_ssh
      ; flags= []
      }
    )
  ; ( "host-ha-xapi-healthcheck"
    , {
        reqd= []
      ; optn= []
      ; help= "Check that xapi on the local host is running satisfactorily."
      ; implementation=
          With_fd_local_session Cli_operations.host_ha_xapi_healthcheck
      ; flags= [Hidden; Neverforward]
      }
    )
  ; ( "subject-add"
    , {
        reqd= ["subject-name"]
      ; optn= []
      ; help= "Add a subject to the list of subjects that can access the pool"
      ; implementation= No_fd Cli_operations.subject_add
      ; flags= []
      }
    )
  ; ( "subject-remove"
    , {
        reqd= ["subject-uuid"]
      ; optn= []
      ; help=
          "Remove a subject from the list of subjects that can access the pool"
      ; implementation= No_fd Cli_operations.subject_remove
      ; flags= []
      }
    )
  ; ( "subject-role-add"
    , {
        reqd= ["uuid"]
      ; optn= ["role-name"; "role-uuid"]
      ; help= "Add a role to a subject"
      ; implementation= No_fd Cli_operations.subject_role_add
      ; flags= []
      }
    )
  ; ( "subject-role-remove"
    , {
        reqd= ["uuid"]
      ; optn= ["role-name"; "role-uuid"]
      ; help= "Remove a role from a subject"
      ; implementation= No_fd Cli_operations.subject_role_remove
      ; flags= []
      }
    )
  ; ( "audit-log-get"
    , {
        reqd= ["filename"]
      ; optn= ["since"]
      ; help= "Write the audit log of the pool to <filename>"
      ; implementation= With_fd Cli_operations.audit_log_get
      ; flags= []
      }
    )
  ; ( "session-subject-identifier-list"
    , {
        reqd= []
      ; optn= []
      ; help=
          "Return a list of all the user subject ids of all \
           externally-authenticated existing sessions"
      ; implementation= No_fd Cli_operations.session_subject_identifier_list
      ; flags= []
      }
    )
  ; ( "session-subject-identifier-logout"
    , {
        reqd= ["subject-identifier"]
      ; optn= []
      ; help=
          "Log out all externally-authenticated sessions associated to a user \
           subject id"
      ; implementation= No_fd Cli_operations.session_subject_identifier_logout
      ; flags= []
      }
    )
  ; ( "session-subject-identifier-logout-all"
    , {
        reqd= []
      ; optn= []
      ; help= "Log out all externally-authenticated sessions"
      ; implementation=
          No_fd Cli_operations.session_subject_identifier_logout_all
      ; flags= []
      }
    )
  ; ( "host-get-server-certificate"
    , {
        reqd= []
      ; optn= []
      ; help= "Get the server TLS certificate of a host"
      ; implementation= No_fd Cli_operations.host_get_server_certificate
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-refresh-server-certificate"
    , {
        reqd= ["host"]
      ; optn= []
      ; help= "Refresh internal server certificate of host"
      ; implementation= No_fd Cli_operations.host_refresh_server_certificate
      ; flags= [Host_selectors]
      }
    )
  ; ( "host-server-certificate-install"
    , {
        reqd= ["certificate"; "private-key"]
      ; optn= ["certificate-chain"]
      ; help= "Install a server TLS certificate on a host"
      ; implementation= With_fd Cli_operations.host_install_server_certificate
      ; flags= [Host_selectors]
      }
    )
  ; ( "secret-create"
    , {
        reqd= ["value"]
      ; optn= []
      ; help= "Create a secret"
      ; implementation= No_fd Cli_operations.secret_create
      ; flags= []
      }
    )
  ; ( "secret-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a secret"
      ; implementation= No_fd Cli_operations.secret_destroy
      ; flags= []
      }
    )
  ; ( "vmss-create"
    , {
        reqd= ["name-label"; "type"; "frequency"]
      ; optn= ["name-description"; "enabled"; "schedule:"; "retained-snapshots"]
      ; help= "Create a VM snapshot schedule."
      ; implementation= No_fd Cli_operations.vmss_create
      ; flags= []
      }
    )
  ; ( "vmss-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a VM snapshot schedule."
      ; implementation= No_fd Cli_operations.vmss_destroy
      ; flags= []
      }
    )
  ; ( "appliance-create"
    , {
        reqd= ["name-label"]
      ; optn= ["name-description"]
      ; help= "Create a VM appliance."
      ; implementation= No_fd Cli_operations.vm_appliance_create
      ; flags= []
      }
    )
  ; ( "appliance-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a VM appliance."
      ; implementation= No_fd Cli_operations.vm_appliance_destroy
      ; flags= []
      }
    )
  ; ( "appliance-start"
    , {
        reqd= ["uuid"]
      ; optn= ["paused"]
      ; help= "Start a VM appliance."
      ; implementation= No_fd Cli_operations.vm_appliance_start
      ; flags= []
      }
    )
  ; ( "appliance-shutdown"
    , {
        reqd= ["uuid"]
      ; optn= ["force"]
      ; help= "Shut down all VMs in a VM appliance."
      ; implementation= No_fd Cli_operations.vm_appliance_shutdown
      ; flags= []
      }
    )
  ; ( "appliance-recover"
    , {
        reqd= ["uuid"]
      ; optn= ["database:"; "force"]
      ; help=
          "Recover a VM appliance from the database contained in the supplied \
           VDI."
      ; implementation= No_fd Cli_operations.vm_appliance_recover
      ; flags= []
      }
    )
  ; ( "appliance-assert-can-be-recovered"
    , {
        reqd= ["uuid"]
      ; optn= ["database:"]
      ; help= "Test whether storage is available to recover this VM appliance."
      ; implementation=
          No_fd Cli_operations.vm_appliance_assert_can_be_recovered
      ; flags= []
      }
    )
  ; ( "gpu-group-create"
    , {
        reqd= ["name-label"]
      ; optn= ["name-description"]
      ; help= "Create an empty GPU group"
      ; implementation= No_fd Cli_operations.gpu_group_create
      ; flags= []
      }
    )
  ; ( "gpu-group-destroy"
    , {
        reqd= ["uuid"]
      ; optn= [""]
      ; help= "Destroy a GPU group"
      ; implementation= No_fd Cli_operations.gpu_group_destroy
      ; flags= []
      }
    )
  ; ( "gpu-group-get-remaining-capacity"
    , {
        reqd= ["uuid"; "vgpu-type-uuid"]
      ; optn= []
      ; help=
          "Calculate the number of VGPUs of the specified type which still be \
           started in the group"
      ; implementation= No_fd Cli_operations.gpu_group_get_remaining_capacity
      ; flags= []
      }
    )
  ; ( "vgpu-create"
    , {
        reqd= ["vm-uuid"; "gpu-group-uuid"]
      ; optn= ["vgpu-type-uuid"; "device"]
      ; help= "Create a vGPU."
      ; implementation= No_fd Cli_operations.vgpu_create
      ; flags= []
      }
    )
  ; ( "vgpu-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a vGPU."
      ; implementation= No_fd Cli_operations.vgpu_destroy
      ; flags= []
      }
    )
  ; ( "drtask-create"
    , {
        reqd= ["type"]
      ; optn= ["device-config:"; "sr-whitelist"]
      ; help= "Create a disaster recovery task."
      ; implementation= No_fd Cli_operations.dr_task_create
      ; flags= []
      }
    )
  ; ( "drtask-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a disaster recovery task."
      ; implementation= No_fd Cli_operations.dr_task_destroy
      ; flags= []
      }
    )
  ; ( "pgpu-enable-dom0-access"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Enable PGPU access to dom0."
      ; implementation= No_fd Cli_operations.pgpu_enable_dom0_access
      ; flags= []
      }
    )
  ; ( "pgpu-disable-dom0-access"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Disable PGPU access to dom0."
      ; implementation= No_fd Cli_operations.pgpu_disable_dom0_access
      ; flags= []
      }
    )
  ; ( "lvhd-enable-thin-provisioning"
    , {
        reqd= ["sr-uuid"; "initial-allocation"; "allocation-quantum"]
      ; optn= []
      ; help= "Enable thin-provisioning on an LVHD SR."
      ; implementation= No_fd Cli_operations.lvhd_enable_thin_provisioning
      ; flags= [Host_selectors]
      }
    )
  ; ( "pvs-site-introduce"
    , {
        reqd= ["name-label"]
      ; optn= ["name-description"; "pvs-uuid"]
      ; help= "Introduce new PVS site"
      ; implementation= No_fd Cli_operations.PVS_site.introduce
      ; flags= []
      }
    )
  ; ( "pvs-site-forget"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Forget a PVS site"
      ; implementation= No_fd Cli_operations.PVS_site.forget
      ; flags= []
      }
    )
  ; ( "pvs-server-introduce"
    , {
        reqd= ["addresses"; "first-port"; "last-port"; "pvs-site-uuid"]
      ; optn= []
      ; help= "Introduce new PVS server"
      ; implementation= No_fd Cli_operations.PVS_server.introduce
      ; flags= []
      }
    )
  ; ( "pvs-server-forget"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Forget a PVS server"
      ; implementation= No_fd Cli_operations.PVS_server.forget
      ; flags= []
      }
    )
  ; ( "pvs-proxy-create"
    , {
        reqd= ["pvs-site-uuid"; "vif-uuid"]
      ; optn= []
      ; help= "Configure a VM/VIF to use a PVS proxy"
      ; implementation= No_fd Cli_operations.PVS_proxy.create
      ; flags= []
      }
    )
  ; ( "pvs-proxy-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Remove (or switch off) a PVS proxy for this VIF/VM"
      ; implementation= No_fd Cli_operations.PVS_proxy.destroy
      ; flags= []
      }
    )
  ; ( "pvs-cache-storage-create"
    , {
        reqd= ["sr-uuid"; "pvs-site-uuid"; "size"]
      ; optn= []
      ; help= "Configure a PVS cache on a given SR for a given host"
      ; implementation= No_fd Cli_operations.PVS_cache_storage.create
      ; flags= [Host_selectors]
      }
    )
  ; ( "pvs-cache-storage-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Remove a PVS cache"
      ; implementation= No_fd Cli_operations.PVS_cache_storage.destroy
      ; flags= []
      }
    )
  ; ( "sdn-controller-introduce"
    , {
        reqd= []
      ; optn= ["address"; "protocol"; "tcp-port"]
      ; help= "Introduce an SDN controller"
      ; implementation= No_fd Cli_operations.SDN_controller.introduce
      ; flags= []
      }
    )
  ; ( "sdn-controller-forget"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Remove an SDN controller"
      ; implementation= No_fd Cli_operations.SDN_controller.forget
      ; flags= []
      }
    )
  ; ( "pusb-scan"
    , {
        reqd= ["host-uuid"]
      ; optn= []
      ; help= "Scan PUSB and update."
      ; implementation= No_fd Cli_operations.PUSB.scan
      ; flags= []
      }
    )
  ; ( "vusb-create"
    , {
        reqd= ["usb-group-uuid"; "vm-uuid"]
      ; optn= []
      ; help= "Create a VUSB."
      ; implementation= No_fd Cli_operations.VUSB.create
      ; flags= []
      }
    )
  ; ( "vusb-unplug"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Unplug vusb device from vm."
      ; implementation= No_fd Cli_operations.VUSB.unplug
      ; flags= []
      }
    )
  ; ( "vusb-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a VUSB."
      ; implementation= No_fd Cli_operations.VUSB.destroy
      ; flags= []
      }
    )
  ; ( "cluster-pool-create"
    , {
        reqd= ["network-uuid"]
      ; optn= ["cluster-stack"; "token-timeout"; "token-timeout-coefficient"]
      ; help= "Create pool-wide cluster"
      ; implementation= No_fd Cli_operations.Cluster.pool_create
      ; flags= []
      }
    )
  ; ( "cluster-pool-force-destroy"
    , {
        reqd= ["cluster-uuid"]
      ; optn= []
      ; help= "Force destroy pool-wide cluster"
      ; implementation= No_fd Cli_operations.Cluster.pool_force_destroy
      ; flags= []
      }
    )
  ; ( "cluster-pool-destroy"
    , {
        reqd= ["cluster-uuid"]
      ; optn= []
      ; help= "Destroy pool-wide cluster"
      ; implementation= No_fd Cli_operations.Cluster.pool_destroy
      ; flags= []
      }
    )
  ; ( "cluster-pool-resync"
    , {
        reqd= ["cluster-uuid"]
      ; optn= []
      ; help= "Resync a cluster across a pool"
      ; implementation= No_fd Cli_operations.Cluster.pool_resync
      ; flags= []
      }
    )
  ; ( "cluster-create"
    , {
        reqd= ["pif-uuid"]
      ; optn=
          [
            "cluster-stack"
          ; "pool-auto-join"
          ; "token-timeout"
          ; "token-timeout-coefficient"
          ]
      ; help= "Create new cluster with master as first member"
      ; implementation= No_fd Cli_operations.Cluster.create
      ; flags= [Hidden]
      }
    )
  ; ( "cluster-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy the pool-wide cluster"
      ; implementation= No_fd Cli_operations.Cluster.destroy
      ; flags= []
      }
    )
  ; ( "cluster-host-create"
    , {
        reqd= ["cluster-uuid"; "host-uuid"; "pif-uuid"]
      ; optn= []
      ; help= "Add a host to an existing cluster"
      ; implementation= No_fd Cli_operations.Cluster_host.create
      ; flags= [Hidden]
      }
    )
  ; ( "cluster-host-disable"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Disable cluster membership for an enabled cluster host"
      ; implementation= No_fd Cli_operations.Cluster_host.disable
      ; flags= []
      }
    )
  ; ( "cluster-host-enable"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Enable cluster membership for a disabled cluster host"
      ; implementation= No_fd Cli_operations.Cluster_host.enable
      ; flags= []
      }
    )
  ; ( "cluster-host-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a cluster host, effectively leaving the cluster"
      ; implementation= No_fd Cli_operations.Cluster_host.destroy
      ; flags= []
      }
    )
  ; ( "cluster-host-force-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Destroy a cluster host object forcefully, effectively leaving the \
           cluster"
      ; implementation= No_fd Cli_operations.Cluster_host.force_destroy
      ; flags= []
      }
    )
  ; ( "repository-introduce"
    , {
        reqd= ["name-label"; "binary-url"; "source-url"; "update"]
      ; optn= ["name-description"; "gpgkey-path"]
      ; help= "Add the configuration for a new remote repository."
      ; implementation= No_fd Cli_operations.Repository.introduce
      ; flags= []
      }
    )
  ; ( "repository-introduce-bundle"
    , {
        reqd= ["name-label"]
      ; optn= ["name-description"]
      ; help= "Add the configuration for a new bundle repository."
      ; implementation= No_fd Cli_operations.Repository.introduce_bundle
      ; flags= []
      }
    )
  ; ( "repository-introduce-remote-pool"
    , {
        reqd= ["name-label"; "binary-url"; "certificate-file"]
      ; optn= ["name-description"]
      ; help= "Add the configuration for a new remote pool repository."
      ; implementation= With_fd Cli_operations.Repository.introduce_remote_pool
      ; flags= []
      }
    )
  ; ( "repository-forget"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Remove the repository record from the database."
      ; implementation= No_fd Cli_operations.Repository.forget
      ; flags= []
      }
    )
  ; ( "repository-set-gpgkey-path"
    , {
        reqd= ["uuid"; "gpgkey-path"]
      ; optn= []
      ; help= "Set the file name of the GPG public key."
      ; implementation= No_fd Cli_operations.Repository.set_gpgkey_path
      ; flags= []
      }
    )
  ; ( "hostdriver-select"
    , {
        reqd= ["uuid"; "variant-name"]
      ; optn= []
      ; help=
          "Select a variant of the specified driver. If no variant of the \
           driver is loaded, this variant will become active. If some other \
           variant is already active, a reboot will be required to activate \
           the new variant."
      ; implementation= No_fd Cli_operations.Host_driver.select
      ; flags= []
      }
    )
  ; ( "hostdriver-deselect"
    , {
        reqd= ["uuid"]
      ; optn= ["force"]
      ; help=
          "Deselect the currently active variant of the specified driver after \
           reboot. No action will be taken if no version is currently active. \
           Potentially dangerous operation, needs the '--force' flag \
           specified."
      ; implementation= No_fd Cli_operations.Host_driver.deselect
      ; flags= []
      }
    )
  ; ( "hostdriver-variant-select"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help=
          "Select a variant of a driver. If no variant of the driver is \
           loaded, this variant will become active. If some other variant is \
           already active, a reboot will be required to activate the new \
           variant."
      ; implementation= No_fd Cli_operations.Driver_variant.select
      ; flags= []
      }
    )
  ; ( "hostdriver-rescan"
    , {
        reqd= []
      ; optn= []
      ; help= "Scan a host and update its driver information."
      ; implementation= No_fd Cli_operations.Host_driver.rescan
      ; flags= [Host_selectors]
      }
    )
  ; ( "vtpm-create"
    , {
        reqd= ["vm-uuid"]
      ; optn= ["is-unique"]
      ; help= "Create a VTPM associated with a VM."
      ; implementation= No_fd Cli_operations.VTPM.create
      ; flags= []
      }
    )
  ; ( "vtpm-destroy"
    , {
        reqd= ["uuid"]
      ; optn= ["force"]
      ; help= "Destroy a VTPM"
      ; implementation= No_fd Cli_operations.VTPM.destroy
      ; flags= []
      }
    )
  ; ( "observer-create"
    , {
        reqd= ["name-label"]
      ; optn=
          [
            "host-uuids"
          ; "name-description"
          ; "enabled"
          ; "attributes"
          ; "endpoints"
          ; "components"
          ]
      ; help=
          "Create a new observer (A High level object that manages data \
           creation and export in the Toolstack)"
      ; implementation= No_fd Cli_operations.Observer.create
      ; flags= []
      }
    )
  ; ( "observer-destroy"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Destroy a provider"
      ; implementation= No_fd Cli_operations.Observer.destroy
      ; flags= []
      }
    )
  ; ( "pci-enable-dom0-access"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Enable PCI access to dom0."
      ; implementation= No_fd Cli_operations.pci_enable_dom0_access
      ; flags= []
      }
    )
  ; ( "pci-disable-dom0-access"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Disable PCI access to dom0."
      ; implementation= No_fd Cli_operations.pci_disable_dom0_access
      ; flags= []
      }
    )
  ; ( "pci-get-dom0-access-status"
    , {
        reqd= ["uuid"]
      ; optn= []
      ; help= "Return a PCI device's dom0 access status."
      ; implementation= No_fd Cli_operations.get_dom0_access_status
      ; flags= []
      }
    )
  ]

let cmdtable : (string, cmd_spec) Hashtbl.t = Hashtbl.create 50

let populated = ref false

let populated_m = Mutex.create ()

let populate_cmdtable rpc session_id =
  Xapi_stdext_threads.Threadext.Mutex.execute populated_m (fun () ->
      if !populated then
        ()
      else (
        List.iter
          (fun (n, c) -> Hashtbl.add cmdtable n c)
          (cmdtable_data @ Cli_operations.gen_cmds rpc session_id) ;
        (* Autogenerated commands too *)
        populated := true
      )
  )

(* ----------------------------------------------------------------------
   Command line lexer and Parser
   ---------------------------------------------------------------------- *)

exception ParseError of string

exception ParamNotFound of string

(* Switches to param mapping *)
let switch_map =
  [
    ("--force", Cli_key.force)
  ; ("--live", Cli_key.live)
  ; ("--internal", Cli_key.internal)
  ; (* show some juicy internal details eg locks *)
    ("-u", Cli_key.username)
  ; ("-pw", Cli_key.password)
  ; ("-s", Cli_key.server)
  ; ("-h", Cli_key.server)
  ; (* Compatability *)
    ("-p", Cli_key.port)
  ; ("--debug", Cli_key.debug)
  ; ("--minimal", Cli_key.minimal)
  ; ("--all", Cli_key.all)
  ]

let convert_switch switch =
  try List.assoc switch switch_map
  with Not_found as e ->
    error "Rethrowing Not_found as ParseError: Unknown switch: %s" switch ;
    Backtrace.reraise e (ParseError ("Unknown switch: " ^ switch))

type token = Id of string | Eq

type commandline = {
    cmdname: string
  ; argv0: string
  ; params: (string * string) list
}

let get_params cmd = cmd.params

let get_cmdname cmd = cmd.cmdname

let get_reqd_param cmd p =
  try List.assoc p cmd.params
  with Not_found as e ->
    error "Rethrowing Not_found as ParamNotFound %s" p ;
    Backtrace.reraise e (ParamNotFound p)

let string_of_token t = match t with Id s -> "Id(" ^ s ^ ")" | Eq -> "Eq"

let starts_with s prefix =
  let s_len = String.length s in
  let p_len = String.length prefix in
  p_len <= s_len && String.sub s 0 p_len = prefix

let rec parse_params_2 xs =
  match xs with
  | p :: ps ->
      (* unary *)
      if starts_with p "--" then
        (String.sub p 2 (String.length p - 2), "true") :: parse_params_2 ps
      else if (* x may be a diadic switch *)
              starts_with p "-" then
        match ps with
        | q :: qs ->
            (convert_switch p, q) :: parse_params_2 qs
        | _ ->
            failwith (Printf.sprintf "Switch %s requires a parameter\n" p)
      else
        let list = String.split_on_char '=' p in
        let param_name = List.hd list in
        let rest = String.concat "=" (List.tl list) in
        (param_name, rest) :: parse_params_2 ps
  | [] ->
      []

let parse_commandline arg_list =
  try
    let argv0 = List.hd arg_list in
    let cmdname = List.hd (List.tl arg_list) in
    (* Detect the case when the command-name is missing *)
    if String.contains cmdname '=' then
      raise (ParseError "command name is missing") ;
    let params = parse_params_2 (List.tl (List.tl arg_list)) in
    {cmdname; argv0; params}
  with e ->
    error "Rethrowing %s as ParseError \"\"" (Printexc.to_string e) ;
    Backtrace.reraise e (ParseError "")

(* ----------------------------------------------------------------------
   Help function
   ---------------------------------------------------------------------- *)

let make_list l =
  let indent = "    " in
  let rec doline cur lines cmds =
    match cmds with
    | [] ->
        List.rev (cur :: lines)
    | cmd :: cmds ->
        if String.length cur + String.length cmd > 74 then
          doline (indent ^ cmd) (cur :: lines) cmds
        else
          doline (cur ^ ", " ^ cmd) lines cmds
  in
  doline (indent ^ List.hd l) [] (List.tl l)

let rio_help printer minimal cmd =
  let docmd cmd =
    match Hashtbl.find_opt cmdtable cmd with
    | Some cmd_spec ->
        let vm_selectors = List.mem Vm_selectors cmd_spec.flags in
        let host_selectors = List.mem Host_selectors cmd_spec.flags in
        let sr_selectors = List.mem Sr_selectors cmd_spec.flags in
        let optional =
          cmd_spec.optn
          @ (if vm_selectors then vmselectors else [])
          @ (if sr_selectors then srselectors else [])
          @ if host_selectors then hostselectors else []
        in
        let desc =
          match (vm_selectors, host_selectors, sr_selectors) with
          | false, false, false ->
              cmd_spec.help
          | true, false, false ->
              cmd_spec.help ^ vmselectorsinfo
          | false, true, false ->
              cmd_spec.help ^ hostselectorsinfo
          | false, false, true ->
              cmd_spec.help ^ srselectorsinfo
          | _ ->
              cmd_spec.help
          (* never happens currently *)
        in
        let recs =
          [
            ("command name        ", cmd)
          ; ("reqd params     ", String.concat ", " cmd_spec.reqd)
          ; ("optional params ", String.concat ", " optional)
          ; ("description     ", desc)
          ]
        in
        printer (Cli_printer.PTable [recs])
    | None ->
        error "Responding with Unknown command %s" cmd ;
        printer (Cli_printer.PList ["Unknown command '" ^ cmd ^ "'"])
  in
  let cmds =
    List.filter
      (fun (x, _) ->
        not
          (List.mem x
             ["server"; "username"; "password"; "port"; "minimal"; "all"]
          )
      )
      cmd.params
  in
  if cmds <> [] then
    List.iter docmd (List.map fst cmds)
  else
    let cmds =
      Hashtbl.fold (fun name cmd list -> (name, cmd) :: list) cmdtable []
    in
    let cmds =
      List.filter (fun (_, cmd) -> not (List.mem Hidden cmd.flags)) cmds
    in
    (* Filter hidden commands from help *)
    let cmds =
      List.sort (fun (name1, _) (name2, _) -> compare name1 name2) cmds
    in
    let help =
      Printf.sprintf
        {|Usage: 
  %s <command>
    [ -s <server> ]            XenServer host
    [ -p <port> ]              XenServer port number
    [ -u <username> -pw <password> | -pwf <password file> ]
                               User authentication (password or file)
    [ --nossl ]                Disable SSL/TLS
    [ --debug ]                Enable debug output
    [ --debug-on-fail ]        Enable debug output only on failure
    [ --traceparent <value> ]  Distributed tracing context
    [ <other arguments> ... ]  Command-specific options

To get help on a specific command: 
  %s help <command>

|}
        cmd.argv0 cmd.argv0
    in
    if List.mem_assoc "all" cmd.params && List.assoc "all" cmd.params = "true"
    then
      let cmds = List.map fst cmds in
      let host_cmds, other =
        List.partition (fun n -> Astring.String.is_prefix ~affix:"host-" n) cmds
      in
      let vm_cmds, other =
        List.partition (fun n -> Astring.String.is_prefix ~affix:"vm-" n) other
      in
      let h = help ^ {|Full command list
-----------------
|} in
      if minimal then
        printer (Cli_printer.PList cmds)
      else (
        printer (Cli_printer.PList [h]) ;
        printer (Cli_printer.PList (make_list host_cmds)) ;
        printer (Cli_printer.PList (make_list [""])) ;
        printer (Cli_printer.PList (make_list vm_cmds)) ;
        printer (Cli_printer.PList (make_list [""])) ;
        printer (Cli_printer.PList (make_list other))
      )
    else
      let cmds =
        List.filter (fun (_, cmd) -> List.mem Standard cmd.flags) cmds
      in
      let cmds = List.map fst cmds in
      let h =
        help
        ^ Printf.sprintf
            {|To get a full listing of commands:
  %s help --all

Common command list
-------------------
|}
            cmd.argv0
      in
      if minimal then
        printer (Cli_printer.PList cmds)
      else (
        printer (Cli_printer.PList [h]) ;
        printer (Cli_printer.PList (make_list cmds))
      )

let cmd_help printer minimal cmd = rio_help printer minimal cmd
