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
(** Module that defines API functions for SR objects
 * @group XenAPI functions
*)

open Xapi_database.Db_filter_types
open API
open Client

(* internal api *)

(**************************************************************************************)
(* current/allowed operations checking                                                *)

open Record_util

(* This is a subset of the API enumeration. Not all values can be included
   because older versions which don't have them are unable to migrate VMs to the
   the versions that have new fields in allowed operations *)
let all_ops : API.storage_operations_set =
  [
    `scan
  ; `destroy
  ; `forget
  ; `plug
  ; `unplug
  ; `vdi_create
  ; `vdi_destroy
  ; `vdi_resize
  ; `vdi_clone
  ; `vdi_snapshot
  ; `vdi_mirror
  ; `vdi_enable_cbt
  ; `vdi_disable_cbt
  ; `vdi_data_destroy
  ; `vdi_list_changed_blocks
  ; `vdi_set_on_boot
  ; `vdi_introduce
  ; `update
  ; `pbd_create
  ; `pbd_destroy
  ]

(* This list comes from https://github.com/xenserver/xen-api/blob/tampa-bugfix/ocaml/xapi/xapi_sr_operations.ml#L36-L38 *)
let all_rpu_ops : API.storage_operations_set =
  [
    `scan
  ; `destroy
  ; `forget
  ; `plug
  ; `unplug
  ; `vdi_create
  ; `vdi_destroy
  ; `vdi_resize
  ; `vdi_clone
  ; `vdi_snapshot
  ; `vdi_introduce
  ; `update
  ; `pbd_create
  ; `pbd_destroy
  ]

let disallowed_during_rpu : API.storage_operations_set =
  List.filter (fun x -> not (List.mem x all_rpu_ops)) all_ops

let sm_cap_table : (API.storage_operations * _) list =
  let open Smint.Feature in
  [
    (`vdi_create, Vdi_create)
  ; (`vdi_destroy, Vdi_delete)
  ; (`vdi_resize, Vdi_resize)
  ; (`vdi_introduce, Vdi_introduce)
  ; (`vdi_mirror, Vdi_mirror)
  ; (`vdi_enable_cbt, Vdi_configure_cbt)
  ; (`vdi_disable_cbt, Vdi_configure_cbt)
  ; (`vdi_data_destroy, Vdi_configure_cbt)
  ; (`vdi_list_changed_blocks, Vdi_configure_cbt)
  ; (`vdi_set_on_boot, Vdi_reset_on_boot)
  ; (`update, Sr_update)
  ; (* We fake clone ourselves *)
    (`vdi_snapshot, Vdi_snapshot)
  ]

type table = (API.storage_operations, (string * string list) option) Hashtbl.t

let features_of_sr_internal ~__context ~_type =
  match
    Db.SM.get_internal_records_where ~__context
      ~expr:(Eq (Field "type", Literal _type))
  with
  | [] ->
      []
  | (_, sm) :: _ ->
      List.filter_map
        (fun (name, v) ->
          try Some (List.assoc name Smint.Feature.string_to_capability_table, v)
          with Not_found -> None
        )
        sm.Db_actions.sM_features

let features_of_sr ~__context record =
  features_of_sr_internal ~__context ~_type:record.Db_actions.sR_type

(** Returns a table of operations -> API error options (None if the operation would be ok)
 * If op is specified, the table may omit reporting errors for ops other than that one. *)
let valid_operations ~__context ?op record _ref' : table =
  let _ref = Ref.string_of _ref' in
  let current_ops = record.Db_actions.sR_current_operations in
  let table : table = Hashtbl.create 10 in
  List.iter (fun x -> Hashtbl.replace table x None) all_ops ;
  let set_errors (code : string) (params : string list)
      (ops : API.storage_operations_set) =
    List.iter
      (fun op ->
        (* Exception can't be raised since the hash table is
           pre-filled for all_ops, and set_errors is applied
           to a subset of all_ops (disallowed_during_rpu) *)
        if Hashtbl.find table op = None then
          Hashtbl.replace table op (Some (code, params))
      )
      ops
  in
  if Helpers.rolling_upgrade_in_progress ~__context then
    set_errors Api_errors.not_supported_during_upgrade [] disallowed_during_rpu ;
  (* Policy:
     Anyone may attach and detach VDIs in parallel but we serialise
     vdi_create, vdi_destroy, vdi_resize operations.
     Multiple simultaneous PBD.unplug operations are ok.
  *)
  let check_sm_features ~__context record =
    let open Smint.Feature in
    (* First consider the backend SM features *)
    let sm_features = features_of_sr ~__context record in
    (* Then filter out the operations we don't want to see for the magic tools SR *)
    let sm_features =
      if record.Db_actions.sR_is_tools_sr then
        List.filter
          (fun f -> not (List.mem (capability_of f) [Vdi_create; Vdi_delete]))
          sm_features
      else
        sm_features
    in
    let forbidden_by_backend =
      List.filter
        (fun op ->
          List.mem_assoc op sm_cap_table
          && not (has_capability (List.assoc op sm_cap_table) sm_features)
        )
        all_ops
    in
    set_errors Api_errors.sr_operation_not_supported [_ref] forbidden_by_backend
  in
  let check_any_attached_pbds ~__context _record =
    (* CA-70294: if the SR has any attached PBDs, destroy and forget operations are not allowed.*)
    let all_pbds_attached_to_this_sr =
      Db.PBD.get_records_where ~__context
        ~expr:
          (And
             ( Eq (Field "SR", Literal _ref)
             , Eq (Field "currently_attached", Literal "true")
             )
          )
    in
    if all_pbds_attached_to_this_sr = [] then
      ()
    else
      set_errors Api_errors.sr_has_pbd [_ref] [`destroy; `forget]
  in
  let check_no_pbds ~__context _record =
    (* If the SR has no PBDs, destroy is not allowed. *)
    if Db.SR.get_PBDs ~__context ~self:_ref' = [] then
      set_errors Api_errors.sr_no_pbds [_ref] [`destroy]
  in
  let check_any_managed_vdis ~__context _record =
    (* If the SR contains any managed VDIs, destroy is not allowed. *)
    (* Iterating through them until we find the first managed one is normally more efficient than calling Db.VDI.get_records_where with managed=true *)
    let vdis = Db.SR.get_VDIs ~__context ~self:_ref' in
    if
      List.exists
        (fun vdi_ref ->
          let vdi = Db.VDI.get_record ~__context ~self:vdi_ref in
          vdi.API.vDI_managed = true && vdi.API.vDI_type <> `rrd
        )
        vdis
    then
      set_errors Api_errors.sr_not_empty [] [`destroy]
  in
  let check_parallel_ops ~__context _record =
    let safe_to_parallelise = [`plug] in
    let current_ops =
      List.sort_uniq
        (fun (_ref1, op1) (_ref2, op2) -> compare op1 op2)
        current_ops
    in
    (* If there are any current operations, all the non_parallelisable operations
       must definitely be stopped *)
    match current_ops with
    | (current_op_ref, current_op_type) :: _ ->
        set_errors Api_errors.other_operation_in_progress
          ["SR"; _ref; sr_operation_to_string current_op_type; current_op_ref]
          (Xapi_stdext_std.Listext.List.set_difference all_ops
             safe_to_parallelise
          ) ;
        let non_parallelisable_op =
          List.find_opt
            (fun (_, op) -> not (List.mem op safe_to_parallelise))
            current_ops
        in
        (* If not all are parallelisable (eg a vdi_resize), ban the otherwise
           parallelisable operations too *)
        Option.iter
          (fun (op_ref, op_type) ->
            set_errors Api_errors.other_operation_in_progress
              ["SR"; _ref; sr_operation_to_string op_type; op_ref]
              safe_to_parallelise
          )
          non_parallelisable_op
    | [] ->
        ()
  in
  let check_cluster_stack_compatible ~__context _record =
    (* Check whether there are any conflicts with HA that prevent us from
     * plugging a PBD for this SR *)
    try
      Cluster_stack_constraints.assert_cluster_stack_compatible ~__context _ref'
    with Api_errors.Server_error (e, args) -> set_errors e args [`plug]
  in
  (* List of (operations * function which checks for errors relevant to those operations) *)
  let relevant_functions =
    [
      (all_ops, check_sm_features)
    ; ([`destroy; `forget], check_any_attached_pbds)
    ; ([`destroy], check_no_pbds)
    ; ([`destroy], check_any_managed_vdis)
    ; (all_ops, check_parallel_ops)
    ; ([`plug], check_cluster_stack_compatible)
    ]
  in
  let relevant_functions =
    match op with
    | None ->
        relevant_functions
    | Some op ->
        List.filter (fun (ops, _) -> List.mem op ops) relevant_functions
  in
  List.iter (fun (_, f) -> f ~__context record) relevant_functions ;
  table

let throw_error (table : table) op =
  match Hashtbl.find_opt table op with
  | None ->
      Helpers.internal_error
        "xapi_sr.assert_operation_valid unknown operation: %s"
        (sr_operation_to_string op)
  | Some (Some (code, params)) ->
      raise (Api_errors.Server_error (code, params))
  | Some None ->
      ()

let assert_operation_valid ~__context ~self ~(op : API.storage_operations) =
  let all = Db.SR.get_record_internal ~__context ~self in
  let table = valid_operations ~__context ~op all self in
  throw_error table op

let update_allowed_operations ~__context ~self : unit =
  let all = Db.SR.get_record_internal ~__context ~self in
  let valid = valid_operations ~__context all self in
  let keys =
    Hashtbl.fold (fun k v acc -> if v = None then k :: acc else acc) valid []
  in
  Db.SR.set_allowed_operations ~__context ~self ~value:keys

let cancel_tasks ~__context ~self ~all_tasks_in_db ~task_ids =
  let ops = Db.SR.get_current_operations ~__context ~self in
  let set value = Db.SR.set_current_operations ~__context ~self ~value in
  Helpers.cancel_tasks ~__context ~ops ~all_tasks_in_db ~task_ids ~set

module C = Storage_interface.StorageAPI (Idl.Exn.GenClient (struct
  let rpc = Storage_access.rpc
end))

let sr_health_check ~__context ~self =
  if Helpers.i_am_srmaster ~__context ~sr:self then
    let dbg = Ref.string_of (Context.get_task_id __context) in
    let info =
      C.SR.stat dbg
        (Storage_interface.Sr.of_string (Db.SR.get_uuid ~__context ~self))
    in
    if
      info.Storage_interface.clustered
      && info.Storage_interface.health = Storage_interface.Recovering
    then
      Helpers.call_api_functions ~__context (fun rpc session_id ->
          let task =
            Client.Task.create ~rpc ~session_id
              ~label:Xapi_globs.sr_health_check_task_label
              ~description:(Ref.string_of self)
          in
          Xapi_host_helpers.update_allowed_operations_all_hosts ~__context ;
          let (_ : Thread.t) =
            Thread.create
              (fun () ->
                let rec loop () =
                  Thread.delay 30. ;
                  let info =
                    C.SR.stat dbg
                      (Storage_interface.Sr.of_string
                         (Db.SR.get_uuid ~__context ~self)
                      )
                  in
                  if
                    (not
                       (Db.Task.get_status ~__context ~self:task = `cancelling)
                    )
                    && info.Storage_interface.clustered
                    && info.Storage_interface.health
                       = Storage_interface.Recovering
                  then
                    loop ()
                  else (
                    Db.Task.destroy ~__context ~self:task ;
                    Xapi_host_helpers.update_allowed_operations_all_hosts
                      ~__context
                  )
                in
                loop ()
              )
              ()
          in
          ()
      )

let stop_health_check_thread ~__context ~self =
  if Helpers.i_am_srmaster ~__context ~sr:self then
    let tasks = Helpers.find_health_check_task ~__context ~sr:self in
    List.iter
      (fun task -> Db.Task.set_status ~__context ~self:task ~value:`cancelling)
      tasks
