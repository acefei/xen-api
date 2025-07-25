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
(** Helper functions relating to VM lifecycle operations.
 * @group Virtual-Machine Management
*)

module D = Debug.Make (struct let name = "xapi_vm_lifecycle" end)

open D
module Rrdd = Rrd_client.Client

let bool_of_assoc key assocs =
  match List.assoc_opt key assocs with
  | Some v ->
      v = "1" || String.lowercase_ascii v = "true"
  | _ ->
      false

(** Given an operation, [allowed_power_states] returns all the possible power state for
    	wich this operation can be performed. *)
let allowed_power_states ~__context ~vmr ~(op : API.vm_operations) =
  let all_power_states = [`Halted; `Paused; `Suspended; `Running] in
  match op with
  (* a VM.import is done on file and not on VMs, so there is not power-state there! *)
  | `import ->
      []
  | `changing_VCPUs | `changing_static_range | `changing_memory_limits ->
      `Halted :: (if vmr.Db_actions.vM_is_control_domain then [`Running] else [])
  | `changing_shadow_memory
  | `changing_NVRAM
  | `make_into_template
  | `provision
  | `start
  | `start_on ->
      [`Halted]
  | `unpause ->
      [`Paused]
  | `csvm | `resume | `resume_on ->
      [`Suspended]
  | `awaiting_memory_live
  | `call_plugin
  | `clean_reboot
  | `clean_shutdown
  | `changing_memory_live
  | `changing_shadow_memory_live
  | `changing_VCPUs_live
  | `data_source_op
  | `pause
  | `pool_migrate
  | `send_sysrq
  | `send_trigger
  | `snapshot_with_quiesce
  | `sysprep
  | `suspend ->
      [`Running]
  | `changing_dynamic_range ->
      [`Halted; `Running]
  | `clone | `copy ->
      `Halted
      ::
      ( if
          vmr.Db_actions.vM_is_a_snapshot
          || Helpers.clone_suspended_vm_enabled ~__context
        then
          [`Suspended]
        else
          []
      )
  | `create_template
  (* Don't touch until XMLRPC unmarshal code is able to pre-blank fields on input. *)
  | `destroy
  | `export ->
      [`Halted; `Suspended]
  | `hard_reboot ->
      [`Paused; `Running]
  | `checkpoint | `get_boot_record | `shutdown | `hard_shutdown ->
      [`Paused; `Suspended; `Running]
  | `migrate_send ->
      [`Halted; `Suspended; `Running]
  | `assert_operation_valid
  | `metadata_export
  | `power_state_reset
  | `revert
  | `reverting
  | `snapshot
  | `update_allowed_operations
  | `query_services ->
      all_power_states
  | `create_vtpm ->
      [`Halted]

(** check if [op] can be done when [vmr] is in [power_state], when no other operation is in progress *)
let is_allowed_sequentially ~__context ~vmr ~power_state ~op =
  List.mem power_state (allowed_power_states ~__context ~vmr ~op)

(**	check if [op] can be done while [current_ops] are already in progress.
   	Remark: we do not test whether the power-state is valid. *)
let is_allowed_concurrently ~(op : API.vm_operations) ~current_ops =
  (* declare below the non-conflicting concurrent sets. *)
  let long_copies = [`clone; `copy; `export]
  and boot_record = [`get_boot_record]
  and snapshot = [`snapshot; `checkpoint]
  and allowed_operations =
    (* a list of valid state -> operation *)
    [
      ([`snapshot_with_quiesce], `snapshot)
    ; ([`migrate_send], `metadata_export)
    ; ([`migrate_send], `clean_shutdown)
    ; ([`migrate_send], `clean_reboot)
    ]
  in
  let state_machine () =
    let current_state = List.map snd current_ops in
    match op with
    | `hard_shutdown ->
        not (List.mem op current_state)
    | `hard_reboot ->
        not
          (List.exists
             (fun o -> List.mem o [`hard_shutdown; `hard_reboot])
             current_state
          )
    | _ ->
        List.exists
          (fun (state, transition) -> state = current_state && transition = op)
          allowed_operations
  in
  let aux ops =
    List.mem op ops && List.for_all (fun (_, o) -> List.mem o ops) current_ops
  in
  aux long_copies || aux snapshot || aux boot_record || state_machine ()

(** True iff the vm guest metrics "other" field includes (feature, "1")
    	as a key-value pair. *)
let has_feature ~vmgmr ~feature =
  match vmgmr with
  | None ->
      false
  | Some gmr -> (
      let other = gmr.Db_actions.vM_guest_metrics_other in
      try List.assoc feature other = "1" with Not_found -> false
    )

let get_feature ~vmgmr ~feature =
  Option.bind vmgmr (fun gmr ->
      let other = gmr.Db_actions.vM_guest_metrics_other in
      List.assoc_opt feature other
  )

(* Returns `true` only if we are certain that the VM has booted PV (if there
 * is no metrics record, then we can't tell) *)
let has_definitely_booted_pv ~vmmr =
  match vmmr with
  | None ->
      false
  | Some r -> (
    match r.Db_actions.vM_metrics_current_domain_type with
    | `hvm | `unspecified ->
        false
    | `pv | `pv_in_pvh | `pvh ->
        true
  )

(** Return an error iff vmr is an HVM guest and lacks a needed feature.

 *  Note: The FreeBSD driver used by NetScaler supports all power actions.
 *  However, older versions of the FreeBSD driver do not explicitly advertise
 *  these support. As a result, xapi does not attempt to signal these power
 *  actions. To address this as a workaround, all power actions should be
 *  permitted for FreeBSD guests.

 *  Additionally, VMs with an explicit `data/cant_suspend_reason` set aren't
 *  allowed to suspend, which would crash Windows and other UEFI VMs.

 *  The "strict" param should be true for determining the allowed_operations list
 *  (which is advisory only) and false (more permissive) when we are potentially about
 *  to perform an operation. This makes a difference for ops that require the guest to
 *  react helpfully. *)
let check_op_for_feature ~__context ~vmr:_ ~vmmr ~vmgmr ~power_state ~op ~ref
    ~strict =
  let implicit_support =
    power_state <> `Running
    (* PV guests offer support implicitly *)
    || has_definitely_booted_pv ~vmmr
    || Xapi_pv_driver_version.(has_pv_drivers (of_guest_metrics vmgmr))
    (* Full PV drivers imply all features *)
  in
  let some_err e = Some (e, [Ref.string_of ref]) in
  let lack_feature feature = not (has_feature ~vmgmr ~feature) in
  match op with
  | `suspend | `checkpoint | `pool_migrate | `migrate_send -> (
    match get_feature ~vmgmr ~feature:"data-cant-suspend-reason" with
    | Some reason ->
        Some (Api_errors.vm_non_suspendable, [Ref.string_of ref; reason])
    | None
      when (not implicit_support) && strict && lack_feature "feature-suspend" ->
        some_err Api_errors.vm_lacks_feature
    | None ->
        None
  )
  | _ when implicit_support ->
      None
  | `clean_shutdown
    when strict
         && lack_feature "feature-shutdown"
         && lack_feature "feature-poweroff" ->
      some_err Api_errors.vm_lacks_feature
  | `clean_reboot
    when strict
         && lack_feature "feature-shutdown"
         && lack_feature "feature-reboot" ->
      some_err Api_errors.vm_lacks_feature
  | `changing_VCPUs_live when lack_feature "feature-vcpu-hotplug" ->
      some_err Api_errors.vm_lacks_feature
  | _ ->
      None

(* N.B. In the pattern matching above, "pat1 | pat2 | pat3" counts as
   	 * one pattern, and the whole thing can be guarded by a "when" clause. *)

(* templates support clone operations, destroy and cross-pool migrate (if not default),
   export, provision, and memory settings change *)
let check_template ~vmr ~op ~ref_str =
  let default_template =
    vmr.Db_actions.vM_is_default_template
    || bool_of_assoc Xapi_globs.default_template_key
         vmr.Db_actions.vM_other_config
  in
  let allowed_operations =
    [
      `changing_dynamic_range
    ; `changing_static_range
    ; `changing_memory_limits
    ; `changing_shadow_memory
    ; `changing_VCPUs
    ; `changing_NVRAM
    ; `clone
    ; `copy
    ; `export
    ; `metadata_export
    ; `provision
    ]
  in
  if
    false
    || List.mem op allowed_operations
    || ((op = `destroy || op = `migrate_send) && not default_template)
  then
    None
  else
    Some
      ( Api_errors.vm_is_template
      , [ref_str; Record_util.vm_operation_to_string op]
      )

let check_snapshot ~vmr:_ ~op ~ref_str =
  let allowed =
    [
      `revert; `clone; `copy; `export; `destroy; `hard_shutdown; `metadata_export
    ]
  in
  if List.mem op allowed then
    None
  else
    Some
      ( Api_errors.vm_is_snapshot
      , [ref_str; Record_util.vm_operation_to_string op]
      )

(* report a power_state/operation error *)
let report_power_state_error ~__context ~vmr ~power_state ~op ~ref_str =
  let expected = allowed_power_states ~__context ~vmr ~op in
  let expected =
    String.concat ", "
      (List.map Record_util.vm_power_state_to_lowercase_string expected)
  in
  let actual = Record_util.vm_power_state_to_lowercase_string power_state in
  Some (Api_errors.vm_bad_power_state, [ref_str; expected; actual])

let report_concurrent_operations_error ~current_ops ~ref_str =
  let current_ops_ref_str, current_ops_str =
    let op_to_str = Record_util.vm_operation_to_string in
    let ( >> ) f g x = g (f x) in
    match current_ops with
    | [] ->
        failwith "No concurrent operation to report"
    | [(op_ref, cop)] ->
        (op_ref, op_to_str cop)
    | l ->
        ( Printf.sprintf "{%s}" (String.concat "," (List.map fst l))
        , Printf.sprintf "{%s}"
            (String.concat "," (List.map (snd >> op_to_str) l))
        )
  in
  Some
    ( Api_errors.other_operation_in_progress
    , ["VM"; ref_str; current_ops_str; current_ops_ref_str]
    )

let check_vgpu ~__context ~op ~ref_str ~vgpus ~power_state =
  let is_migratable vgpu =
    try
      (* Prevent VMs with VGPU from being migrated from pre-Jura to Jura and later hosts during RPU *)
      let host_from =
        Db.VGPU.get_VM ~__context ~self:vgpu |> fun vm ->
        Db.VM.get_resident_on ~__context ~self:vm |> fun host ->
        Helpers.LocalObject host
      in
      (* true if platform version of host_from more than inverness' 2.4.0 *)
      Helpers.(
        compare_int_lists
          (version_of ~__context host_from)
          platform_version_inverness
      )
      > 0
    with e ->
      debug "is_migratable: %s" (ExnHelper.string_of_exn e) ;
      (* best effort: yes if not possible to decide *)
      true
  in
  let is_suspendable vgpu =
    Db.VGPU.get_type ~__context ~self:vgpu |> fun self ->
    Db.VGPU_type.get_implementation ~__context ~self |> function
    | `nvidia | `nvidia_sriov ->
        let pgpu = Db.VGPU.get_resident_on ~__context ~self:vgpu in
        Db.is_valid_ref __context pgpu
        && Db.PGPU.get_compatibility_metadata ~__context ~self:pgpu
           |> List.mem_assoc Xapi_gpumon.Nvidia.key
    | _ ->
        false
  in
  match op with
  | `migrate_send when power_state = `Halted ->
      None
  | (`pool_migrate | `migrate_send)
    when List.for_all is_migratable vgpus && List.for_all is_suspendable vgpus
    ->
      None
  | `checkpoint when power_state = `Suspended ->
      None
  | (`suspend | `checkpoint) when List.for_all is_suspendable vgpus ->
      None
  | `pool_migrate | `migrate_send | `suspend | `checkpoint ->
      Some (Api_errors.vm_has_vgpu, [ref_str])
  | _ ->
      None

(* VM cannot be converted into a template while it is a member of an appliance. *)
let check_appliance ~vmr ~op ~ref_str =
  match op with
  | `make_into_template ->
      Some
        ( Api_errors.vm_is_part_of_an_appliance
        , [ref_str; Ref.string_of vmr.Db_actions.vM_appliance]
        )
  | _ ->
      None

(* VM cannot be converted into a template while it is assigned to a protection policy. *)
let check_protection_policy ~vmr ~op ~ref_str =
  match op with
  | `make_into_template ->
      Some
        ( Api_errors.vm_assigned_to_protection_policy
        , [ref_str; Ref.string_of vmr.Db_actions.vM_protection_policy]
        )
  | _ ->
      None

(* VM cannot be converted into a template while it is assigned to a snapshot schedule. *)
let check_snapshot_schedule ~vmr ~ref_str = function
  | `make_into_template ->
      Some
        ( Api_errors.vm_assigned_to_snapshot_schedule
        , [ref_str; Ref.string_of vmr.Db_actions.vM_snapshot_schedule]
        )
  | _ ->
      None

(** Some VMs can't migrate. The predicate [is_mobile] is true, if and
 * only if a VM is mobile.
 *
 * A VM is not mobile if any following values are true:
 * [platform:nomigrate] or [platform:nested-virt].  A VM can always
 * migrate if strict=false.
 *
 * The values of [platform:nomigrate] and [platform:nested-virt] are
 * captured by Xenopsd when a VM starts, reported to Xapi, and kept in
 * the VM_metrics data model.
 *
 * If the VM_metrics object does not exist, it implies the VM is not
 * running - in which case we use the current values from the database.
 **)

let nomigrate ~__context vm metrics =
  try Db.VM_metrics.get_nomigrate ~__context ~self:metrics
  with _ ->
    let platformdata = Db.VM.get_platform ~__context ~self:vm in
    let key = "nomigrate" in
    Vm_platform.is_true ~key ~platformdata ~default:false

let nested_virt ~__context vm metrics =
  try Db.VM_metrics.get_nested_virt ~__context ~self:metrics
  with _ ->
    let platformdata = Db.VM.get_platform ~__context ~self:vm in
    let key = "nested-virt" in
    Vm_platform.is_true ~key ~platformdata ~default:false

let is_mobile ~__context vm strict metrics =
  (not @@ nomigrate ~__context vm metrics)
  && (not @@ nested_virt ~__context vm metrics)
  || not strict

let maybe_get_metrics ~__context ~ref =
  if Db.is_valid_ref __context ref then
    Some (Db.VM_metrics.get_record_internal ~__context ~self:ref)
  else
    None

let maybe_get_guest_metrics ~__context ~ref =
  if Db.is_valid_ref __context ref then
    Some (Db.VM_guest_metrics.get_record_internal ~__context ~self:ref)
  else
    None

(* PCI devices that belong to NVIDIA SRIOV cards *)
let nvidia_sriov_pcis ~__context vgpus =
  vgpus
  |> List.filter_map (fun vgpu ->
         Db.VGPU.get_type ~__context ~self:vgpu |> fun typ ->
         Db.VGPU_type.get_implementation ~__context ~self:typ |> function
         | `nvidia_sriov ->
             let pci = Db.VGPU.get_PCI ~__context ~self:vgpu in
             if Db.is_valid_ref __context pci then Some pci else None
         | _ ->
             None
     )

(** Take an internal VM record and a proposed operation. Return None iff the operation
    would be acceptable; otherwise Some (Api_errors.<something>, [list of strings])
    corresponding to the first error found. Checking stops at the first error.
    The "strict" param sets whether we require feature-flags for ops that need guest
    support: ops in the suspend-like and shutdown-like categories. *)
let check_operation_error ~__context ~ref =
  let vmr = Db.VM.get_record_internal ~__context ~self:ref in
  let vmmr = maybe_get_metrics ~__context ~ref:vmr.Db_actions.vM_metrics in
  let vmgmr =
    maybe_get_guest_metrics ~__context ~ref:vmr.Db_actions.vM_guest_metrics
  in
  let ref_str = Ref.string_of ref in
  let power_state = vmr.Db_actions.vM_power_state in
  let is_template = vmr.Db_actions.vM_is_a_template in
  let is_snapshot = vmr.Db_actions.vM_is_a_snapshot in
  let vdis =
    List.filter_map
      (fun vbd ->
        try Some (Db.VBD.get_VDI ~__context ~self:vbd) with _ -> None
      )
      vmr.Db_actions.vM_VBDs
    |> List.filter (Db.is_valid_ref __context)
  in
  let current_ops = vmr.Db_actions.vM_current_operations in
  let metrics = Db.VM.get_metrics ~__context ~self:ref in
  let is_nested_virt = nested_virt ~__context ref metrics in
  let is_domain_zero =
    Db.VM.get_by_uuid ~__context ~uuid:vmr.Db_actions.vM_uuid
    |> Helpers.is_domain_zero ~__context
  in
  let vdis_reset_and_caching =
    List.filter_map
      (fun vdi ->
        try
          let sm_config = Db.VDI.get_sm_config ~__context ~self:vdi in
          Some
            ( List.assoc_opt "on_boot" sm_config = Some "reset"
            , bool_of_assoc "caching" sm_config
            )
        with _ -> None
      )
      vdis
  in
  let sriov_pcis = nvidia_sriov_pcis ~__context vmr.Db_actions.vM_VGPUs in
  let is_not_sriov pci = not @@ List.mem pci sriov_pcis in
  let pcis = vmr.Db_actions.vM_attached_PCIs in
  let is_appliance_valid =
    Db.is_valid_ref __context vmr.Db_actions.vM_appliance
  in
  let is_protection_policy_valid =
    Db.is_valid_ref __context vmr.Db_actions.vM_protection_policy
  in
  let rolling_upgrade_in_progress =
    Helpers.rolling_upgrade_in_progress ~__context
  in
  let is_snapshort_schedule_valid =
    Db.is_valid_ref __context vmr.Db_actions.vM_snapshot_schedule
  in

  fun ~op ~strict ->
    let current_error = None in
    let check c f = match c with Some e -> Some e | None -> f () in
    (* Check if the operation has been explicitly blocked by the/a user *)
    let current_error =
      check current_error (fun () ->
          Option.map
            (fun v -> (Api_errors.operation_blocked, [ref_str; v]))
            (List.assoc_opt op vmr.Db_actions.vM_blocked_operations)
      )
    in
    (* Always check the power state constraint of the operation first *)
    let current_error =
      check current_error (fun () ->
          if not (is_allowed_sequentially ~__context ~vmr ~power_state ~op) then
            report_power_state_error ~__context ~vmr ~power_state ~op ~ref_str
          else
            None
      )
    in
    (* if other operations are in progress, check that the new operation is allowed concurrently with them. *)
    let current_error =
      check current_error (fun () ->
          if
            List.length current_ops <> 0
            && not (is_allowed_concurrently ~op ~current_ops)
          then
            report_concurrent_operations_error ~current_ops ~ref_str
          else
            None
      )
    in
    (* if the VM is a template, check the template behavior exceptions. *)
    let current_error =
      check current_error (fun () ->
          if is_template && not is_snapshot then
            check_template ~vmr ~op ~ref_str
          else
            None
      )
    in
    (* if the VM is a snapshot, check the snapshot behavior exceptions. *)
    let current_error =
      check current_error (fun () ->
          if is_snapshot then
            check_snapshot ~vmr ~op ~ref_str
          else
            None
      )
    in
    (* if the VM is neither a template nor a snapshot, do not allow provision and revert. *)
    let current_error =
      check current_error (fun () ->
          if op = `provision && not is_template then
            Some (Api_errors.only_provision_template, [])
          else
            None
      )
    in
    let current_error =
      check current_error (fun () ->
          if op = `revert && not is_snapshot then
            Some (Api_errors.only_revert_snapshot, [])
          else
            None
      )
    in
    (* Some ops must be blocked if VM is not mobile *)
    let current_error =
      check current_error (fun () ->
          match op with
          | (`suspend | `checkpoint | `pool_migrate | `migrate_send)
            when not (is_mobile ~__context ref strict metrics) ->
              Some (Api_errors.vm_is_immobile, [ref_str])
          | _ ->
              None
      )
    in
    let current_error =
      check current_error (fun () ->
          match op with
          | `changing_dynamic_range when is_nested_virt && strict ->
              Some (Api_errors.vm_is_using_nested_virt, [ref_str])
          | _ ->
              None
      )
    in
    (* Check if the VM is a control domain (eg domain 0).            *)
    (* FIXME: Instead of special-casing for the control domain here, *)
    (* make use of the Helpers.ballooning_enabled_for_vm function.   *)
    let current_error =
      check current_error (fun () ->
          if (op = `changing_VCPUs || op = `destroy) && is_domain_zero then
            Some
              ( Api_errors.operation_not_allowed
              , ["This operation is not allowed on dom0"]
              )
          else if
            vmr.Db_actions.vM_is_control_domain
            && op <> `data_source_op
            && op <> `changing_memory_live
            && op <> `awaiting_memory_live
            && op <> `metadata_export
            && op <> `changing_dynamic_range
            && op <> `changing_memory_limits
            && op <> `changing_static_range
            && op <> `start
            && op <> `start_on
            && op <> `changing_VCPUs
            && op <> `destroy
          then
            Some
              ( Api_errors.operation_not_allowed
              , ["This operation is not allowed on a control domain"]
              )
          else
            None
      )
    in
    (* check for any HVM guest feature needed by the op *)
    let current_error =
      check current_error (fun () ->
          check_op_for_feature ~__context ~vmr ~vmmr ~vmgmr ~power_state ~op
            ~ref ~strict
      )
    in
    (* VSS support has been removed *)
    let current_error =
      check current_error (fun () ->
          if op = `snapshot_with_quiesce then
            Some (Api_errors.vm_snapshot_with_quiesce_not_supported, [ref_str])
          else
            None
      )
    in
    (* Check for an error due to VDI caching/reset behaviour *)
    let current_error =
      check current_error (fun () ->
          if
            op = `checkpoint
            || op = `snapshot
            || op = `suspend
            || op = `snapshot_with_quiesce
          then
            (* If any vdi exists with on_boot=reset, then disallow checkpoint, snapshot, suspend *)
            if List.exists fst vdis_reset_and_caching then
              Some (Api_errors.vdi_on_boot_mode_incompatible_with_operation, [])
            else
              None
          else if op = `pool_migrate then
            (* If any vdi exists with on_boot=reset and caching is enabled, disallow migrate *)
            if
              List.exists
                (fun (reset, caching) -> reset && caching)
                vdis_reset_and_caching
            then
              Some (Api_errors.vdi_on_boot_mode_incompatible_with_operation, [])
            else
              None
          else
            None
      )
    in
    (* If a PCI device is passed-through, check if the operation is allowed *)
    let current_error =
      check current_error @@ fun () ->
      match op with
      | (`suspend | `checkpoint | `pool_migrate | `migrate_send)
        when List.exists is_not_sriov pcis ->
          Some (Api_errors.vm_has_pci_attached, [ref_str])
      | _ ->
          None
    in
    (* The VM has a VGPU, check if the operation is allowed*)
    let current_error =
      check current_error (fun () ->
          if vmr.Db_actions.vM_VGPUs <> [] then
            check_vgpu ~__context ~op ~ref_str ~vgpus:vmr.Db_actions.vM_VGPUs
              ~power_state
          else
            None
      )
    in
    (* The VM has a VUSB, check if the operation is allowed*)
    let current_error =
      check current_error (fun () ->
          match op with
          | (`suspend | `snapshot | `checkpoint | `migrate_send | `pool_migrate)
            when vmr.Db_actions.vM_VUSBs <> [] ->
              Some (Api_errors.vm_has_vusbs, [ref_str])
          | _ ->
              None
      )
    in
    (* Check for errors caused by VM being in an appliance. *)
    let current_error =
      check current_error (fun () ->
          if is_appliance_valid then
            check_appliance ~vmr ~op ~ref_str
          else
            None
      )
    in
    (* Check for errors caused by VM being assigned to a protection policy. *)
    let current_error =
      check current_error (fun () ->
          if is_protection_policy_valid then
            check_protection_policy ~vmr ~op ~ref_str
          else
            None
      )
    in
    (* Check for errors caused by VM being assigned to a snapshot schedule. *)
    let current_error =
      check current_error (fun () ->
          if is_snapshort_schedule_valid then
            check_snapshot_schedule ~vmr ~ref_str op
          else
            None
      )
    in
    (* Check whether this VM needs to be a system domain. *)
    let current_error =
      check current_error (fun () ->
          if
            op = `query_services
            && not
                 (bool_of_assoc "is_system_domain"
                    vmr.Db_actions.vM_other_config
                 )
          then
            Some (Api_errors.not_system_domain, [ref_str])
          else
            None
      )
    in
    let current_error =
      check current_error (fun () ->
          if
            rolling_upgrade_in_progress
            && not (List.mem op Xapi_globs.rpu_allowed_vm_operations)
          then
            Some (Api_errors.not_supported_during_upgrade, [])
          else
            None
      )
    in
    (* We can only add a VTPM if there is none already *)
    let current_error =
      check current_error (fun () ->
          match op with
          | `create_vtpm when vmr.Db_actions.vM_VTPMs <> [] ->
              let count = List.length vmr.Db_actions.vM_VTPMs in
              Some (Api_errors.vtpm_max_amount_reached, [string_of_int count])
          | _ ->
              None
      )
    in
    current_error

let get_operation_error ~__context ~self ~op ~strict =
  check_operation_error ~__context ~ref:self ~op ~strict

let assert_operation_valid ~__context ~self ~op ~strict =
  match get_operation_error ~__context ~self ~op ~strict with
  | None ->
      ()
  | Some (a, b) ->
      raise (Api_errors.Server_error (a, b))

(* can't put this into xapi_vtpm because it creates a cycle *)
let vtpm_update_allowed_operations ~__context ~self =
  let vm = Db.VTPM.get_VM ~__context ~self in
  let state = Db.VM.get_power_state ~__context ~self:vm in
  let ops = [`destroy] in
  let allowed = match state with `Halted -> ops | _ -> [] in
  Db.VTPM.set_allowed_operations ~__context ~self ~value:allowed

let ignored_ops =
  [
    `create_template
  ; `power_state_reset
  ; `csvm
  ; `get_boot_record
  ; `send_sysrq
  ; `send_trigger
  ; `query_services
  ; `shutdown
  ; `call_plugin
  ; `changing_memory_live
  ; `awaiting_memory_live
  ; `changing_memory_limits
  ; `changing_shadow_memory_live
  ; `changing_VCPUs
  ; `assert_operation_valid
  ; `data_source_op
  ; `update_allowed_operations
  ; `import
  ; `reverting
  ]

let allowable_ops =
  List.filter (fun op -> not (List.mem op ignored_ops)) API.vm_operations__all

let update_allowed_operations ~__context ~self =
  let check' = check_operation_error ~__context ~ref:self in
  let check accu op =
    match check' ~op ~strict:true with None -> op :: accu | Some _err -> accu
  in
  let allowed = List.fold_left check [] allowable_ops in
  (* FIXME: need to be able to deal with rolling-upgrade for orlando as well *)
  let allowed =
    if Helpers.rolling_upgrade_in_progress ~__context then
      Xapi_stdext_std.Listext.List.intersect allowed
        Xapi_globs.rpu_allowed_vm_operations
    else
      allowed
  in
  Db.VM.set_allowed_operations ~__context ~self ~value:allowed ;
  (* Update the appliance's allowed operations. *)
  let appliance = Db.VM.get_appliance ~__context ~self in
  if Db.is_valid_ref __context appliance then
    Xapi_vm_appliance_lifecycle.update_allowed_operations ~__context
      ~self:appliance ;
  (* Update VTPMs' allowed_operations *)
  Db.VM.get_VTPMs ~__context ~self
  |> List.filter (Db.is_valid_ref __context)
  |> List.iter @@ fun self -> vtpm_update_allowed_operations ~__context ~self

let checkpoint_in_progress ~__context ~vm =
  Xapi_stdext_std.Listext.List.setify
    (List.map snd (Db.VM.get_current_operations ~__context ~self:vm))
  |> List.mem `checkpoint

let remove_pending_guidance ~__context ~self ~value =
  let v = Db.VM.get_name_label ~__context ~self in
  if
    List.exists
      (fun g -> g = value)
      (Db.VM.get_pending_guidances ~__context ~self)
  then (
    debug "Remove guidance [%s] from vm [%s]'s pending_guidances list"
      Updateinfo.Guidance.(of_pending_guidance value |> to_string)
      v ;
    Db.VM.remove_pending_guidances ~__context ~self ~value
  ) ;

  if
    List.exists
      (fun g -> g = value)
      (Db.VM.get_pending_guidances_recommended ~__context ~self)
  then (
    debug
      "Remove guidance [%s] from vm [%s]'s pending_guidances_recommended list"
      Updateinfo.Guidance.(of_pending_guidance value |> to_string)
      v ;
    Db.VM.remove_pending_guidances_recommended ~__context ~self ~value
  ) ;

  if
    List.exists
      (fun g -> g = value)
      (Db.VM.get_pending_guidances_full ~__context ~self)
  then (
    debug "Remove guidance [%s] from vm [%s]'s pending_guidances_full list"
      Updateinfo.Guidance.(of_pending_guidance value |> to_string)
      v ;
    Db.VM.remove_pending_guidances_full ~__context ~self ~value
  )

(** 1. Called on new VMs (clones, imports) and on server start to manually refresh
    the power state, allowed_operations field etc.  Current-operations won't be
    cleaned
    2. Called on update VM when the power state changes *)
let force_state_reset_keep_current_operations ~__context ~self ~value:state =
  (* First update the power_state. Some operations below indirectly rely on this. *)
  let old_state = Db.VM.get_power_state ~__context ~self in
  Db.VM.set_power_state ~__context ~self ~value:state ;
  if state = `Suspended then
    remove_pending_guidance ~__context ~self ~value:`restart_device_model ;
  if state = `Halted then (
    (* mark all devices as disconnected *)
    List.iter
      (fun vbd ->
        Db.VBD.set_currently_attached ~__context ~self:vbd ~value:false ;
        Db.VBD.set_reserved ~__context ~self:vbd ~value:false ;
        Xapi_vbd_helpers.clear_current_operations ~__context ~self:vbd
      )
      (Db.VM.get_VBDs ~__context ~self) ;
    List.iter
      (fun vif ->
        Db.VIF.set_currently_attached ~__context ~self:vif ~value:false ;
        Db.VIF.set_reserved ~__context ~self:vif ~value:false ;
        Db.VIF.set_reserved_pci ~__context ~self:vif ~value:Ref.null ;
        Xapi_vif_helpers.clear_current_operations ~__context ~self:vif ;
        Option.iter
          (fun p -> Pvs_proxy_control.clear_proxy_state ~__context vif p)
          (Pvs_proxy_control.find_proxy_for_vif ~__context ~vif)
      )
      (Db.VM.get_VIFs ~__context ~self) ;
    List.iter
      (fun vgpu ->
        Db.VGPU.set_currently_attached ~__context ~self:vgpu ~value:false ;
        let keys = Db.VGPU.get_compatibility_metadata ~__context ~self:vgpu in
        if List.mem_assoc Xapi_gpumon.Nvidia.key keys then (
          warn "Found unexpected Nvidia compat metadata on vGPU %s / VM %s"
            (Ref.string_of vgpu) (Ref.string_of self) ;
          let v =
            List.filter (fun (k, _) -> k <> Xapi_gpumon.Nvidia.key) keys
          in
          Db.VGPU.set_compatibility_metadata ~__context ~self:vgpu ~value:v ;
          debug "Clearing Nvidia vGPU %s compat metadata" (Ref.string_of vgpu)
        )
      )
      (Db.VM.get_VGPUs ~__context ~self) ;
    List.iter
      (fun vusb ->
        Db.VUSB.set_currently_attached ~__context ~self:vusb ~value:false ;
        Xapi_vusb_helpers.clear_current_operations ~__context ~self:vusb
      )
      (Db.VM.get_VUSBs ~__context ~self) ;
    (* Blank the requires_reboot flag *)
    Db.VM.set_requires_reboot ~__context ~self ~value:false ;
    remove_pending_guidance ~__context ~self ~value:`restart_device_model ;
    remove_pending_guidance ~__context ~self ~value:`restart_vm
  ) ;
  (* Do not clear resident_on for VM and VGPU in a checkpoint operation *)
  if
    state = `Halted
    || (state = `Suspended && not (checkpoint_in_progress ~__context ~vm:self))
  then (
    Db.VM.set_resident_on ~__context ~self ~value:Ref.null ;
    (* make sure we aren't reserving any memory for this VM *)
    Db.VM.set_scheduled_to_be_resident_on ~__context ~self ~value:Ref.null ;
    Db.VM.set_domid ~__context ~self ~value:(-1L) ;
    (* release vGPUs associated with VM *)
    Db.VM.get_VGPUs ~__context ~self
    |> List.iter (fun vgpu ->
           Db.VGPU.set_resident_on ~__context ~self:vgpu ~value:Ref.null ;
           Db.VGPU.set_scheduled_to_be_resident_on ~__context ~self:vgpu
             ~value:Ref.null ;
           Db.VGPU.set_PCI ~__context ~self:vgpu ~value:Ref.null
       ) ;
    Db.VM.get_attached_PCIs ~__context ~self
    |> List.iter (fun pci ->
           if Db.is_valid_ref __context pci then
             Db.PCI.remove_attached_VMs ~__context ~self:pci ~value:self
           else
             (* XSI-995 pci does not exist, so remove it from the vm record *)
             Db.VM.remove_attached_PCIs ~__context ~self ~value:pci
       ) ;
    List.iter
      (fun pci ->
        (* The following should not be necessary if many-to-many relations in the DB
         * work properly. People have reported issues that may indicate that this is
         * not the case, but we have not yet found the root cause. Therefore, the
         * following code is there "just to be sure".*)
        if List.mem self (Db.PCI.get_attached_VMs ~__context ~self:pci) then
          Db.PCI.remove_attached_VMs ~__context ~self:pci ~value:self ;
        (* Clear any PCI device reservations for this VM. *)
        if Db.PCI.get_scheduled_to_be_attached_to ~__context ~self:pci = self
        then
          Db.PCI.set_scheduled_to_be_attached_to ~__context ~self:pci
            ~value:Ref.null
      )
      (Db.PCI.get_all ~__context)
  ) ;
  update_allowed_operations ~__context ~self ;
  if old_state <> state && (old_state = `Running || state = `Running) then
    Xapi_vm_group_helpers.maybe_update_vm_anti_affinity_alert_for_vm ~__context
      ~vm:self ;
  if state = `Halted then (* archive the rrd for this vm *)
    let vm_uuid = Db.VM.get_uuid ~__context ~self in
    let master_address = Pool_role.get_master_address_opt () in
    log_and_ignore_exn (fun () -> Rrdd.archive_rrd vm_uuid master_address)

(** Called on new VMs (clones, imports) and on server start to manually refresh
    the power state, allowed_operations field etc.  Clean current-operations
    as well *)
let force_state_reset ~__context ~self ~value:state =
  if Db.VM.get_current_operations ~__context ~self <> [] then
    Db.VM.set_current_operations ~__context ~self ~value:[] ;
  force_state_reset_keep_current_operations ~__context ~self ~value:state

let cancel_tasks ~__context ~self ~all_tasks_in_db ~task_ids =
  let ops = Db.VM.get_current_operations ~__context ~self in
  let set value = Db.VM.set_current_operations ~__context ~self ~value in
  Helpers.cancel_tasks ~__context ~ops ~all_tasks_in_db ~task_ids ~set

(** Assert that VM is in a certain set of states before starting an operation *)
let assert_initial_power_state_in ~__context ~self ~allowed =
  let actual = Db.VM.get_power_state ~__context ~self in
  if not (List.mem actual allowed) then
    raise
      (Api_errors.Server_error
         ( Api_errors.vm_bad_power_state
         , [
             Ref.string_of self
           ; List.map Record_util.vm_power_state_to_lowercase_string allowed
             |> String.concat ";"
           ; Record_util.vm_power_state_to_lowercase_string actual
           ]
         )
      )

(** Assert that VM is in a certain state before starting an operation *)
let assert_initial_power_state_is ~expected =
  assert_initial_power_state_in ~allowed:[expected]

(** Assert that VM is in a certain set of states after completing an operation *)
let assert_final_power_state_in ~__context ~self ~allowed =
  let actual = Db.VM.get_power_state ~__context ~self in
  if not (List.mem actual allowed) then
    Helpers.internal_error
      "VM not in expected power state after completing operation: %s, %s, %s"
      (Ref.string_of self)
      (List.map Record_util.vm_power_state_to_lowercase_string allowed
      |> String.concat ";"
      )
      (Record_util.vm_power_state_to_lowercase_string actual)

(** Assert that VM is in a certain state after completing an operation *)
let assert_final_power_state_is ~expected =
  assert_final_power_state_in ~allowed:[expected]
