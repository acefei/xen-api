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
module Rrdd = Rrd_client.Client

let with_lock = Xapi_stdext_threads.Threadext.Mutex.execute

module Listext = Xapi_stdext_std.Listext
module Unixext = Xapi_stdext_unix.Unixext

let finally = Xapi_stdext_pervasives.Pervasiveext.finally

module Redo_log = Xapi_database.Redo_log
open Xapi_database.Db_filter_types
open API
open Client

(* internal api *)

module D = Debug.Make (struct let name = "xapi_sr" end)

open D

(**************************************************************************************)

(* Limit us to a single scan per SR at a time: any other thread that turns up gets
   immediately rejected *)
let scans_in_progress = Hashtbl.create 10

let scans_in_progress_m = Mutex.create ()

let scans_in_progress_c = Condition.create ()

let i_should_scan_sr sr =
  with_lock scans_in_progress_m (fun () ->
      if Hashtbl.mem scans_in_progress sr then
        false (* someone else already is *)
      else (
        Hashtbl.replace scans_in_progress sr true ;
        true
      )
  )

let scan_finished sr =
  with_lock scans_in_progress_m (fun () ->
      Hashtbl.remove scans_in_progress sr ;
      Condition.broadcast scans_in_progress_c
  )

module Size = struct let n () = !Xapi_globs.max_active_sr_scans end

module AutoScanThrottle = Throttle.Make (Size)
module SRScanThrottle = Throttle.Make (Size)

(* Perform a single scan of an SR in a background thread. Limit to one thread per SR *)
(* If a callback is supplied, call it once the scan is complete. *)
let scan_one ~__context ?callback sr =
  let sr_uuid = Db.SR.get_uuid ~__context ~self:sr in
  if i_should_scan_sr sr then
    ignore
      (Thread.create
         (fun () ->
           Server_helpers.exec_with_subtask ~__context "scan one"
             (fun ~__context ->
               finally
                 (fun () ->
                   try
                     AutoScanThrottle.execute (fun () ->
                         Helpers.call_api_functions ~__context
                           (fun rpc session_id ->
                             Helpers.log_exn_continue
                               (Printf.sprintf "scanning SR %s"
                                  (Ref.string_of sr)
                               )
                               (fun sr -> Client.SR.scan ~rpc ~session_id ~sr)
                               sr
                         )
                     )
                   with e ->
                     error "Caught exception attempting an SR.scan: %s"
                       (ExnHelper.string_of_exn e)
                 )
                 (fun () ->
                   scan_finished sr ;
                   debug "Scan of SR %s complete." sr_uuid ;
                   Option.iter
                     (fun f ->
                       debug "Starting callback for SR %s." sr_uuid ;
                       f () ;
                       debug "Callback for SR %s finished." sr_uuid
                     )
                     callback
                 )
           )
         )
         ()
      )
  else
    (* If a callback was supplied but a scan is already in progress, call the callback once the scan is complete. *)
    Option.iter
      (fun f ->
        ignore
          (Thread.create
             (fun () ->
               debug
                 "Tried to scan SR %s but scan already in progress - waiting \
                  for scan to complete."
                 sr_uuid ;
               with_lock scans_in_progress_m (fun () ->
                   while Hashtbl.mem scans_in_progress sr do
                     Condition.wait scans_in_progress_c scans_in_progress_m
                   done
               ) ;
               debug
                 "Got signal that scan of SR %s is complete - starting \
                  callback."
                 sr_uuid ;
               f () ;
               debug "Callback for SR %s finished." sr_uuid
             )
             ()
          )
      )
      callback

let scan_all ~__context =
  let srs = Helpers.get_all_plugged_srs ~__context in
  (* only scan those with the dirty/auto_scan key set *)
  let scannable_srs =
    List.filter
      (fun sr ->
        let oc = Db.SR.get_other_config ~__context ~self:sr in
        List.mem_assoc Xapi_globs.auto_scan oc
        && List.assoc Xapi_globs.auto_scan oc = "true"
        || List.mem_assoc "dirty" oc
      )
      srs
  in
  if scannable_srs <> [] then
    debug "Automatically scanning SRs = [ %s ]"
      (String.concat ";" (List.map Ref.string_of scannable_srs)) ;
  List.iter (scan_one ~__context) scannable_srs

let scanning_thread () =
  Debug.with_thread_named "scanning_thread"
    (fun () ->
      Server_helpers.exec_with_new_task "SR scanner" (fun __context ->
          let host = Helpers.get_localhost ~__context in
          let get_delay () =
            try
              let oc = Db.Host.get_other_config ~__context ~self:host in
              float_of_string (List.assoc Xapi_globs.auto_scan_interval oc)
            with _ -> 30.
          in
          while true do
            Thread.delay (get_delay ()) ;
            try scan_all ~__context
            with e ->
              debug "Exception in SR scanning thread: %s" (Printexc.to_string e)
          done
      )
    )
    ()

(* introduce, creates a record for the SR in the database. It has no other side effect *)
let introduce ~__context ~uuid ~name_label ~name_description ~_type
    ~content_type ~shared ~sm_config =
  let _type = String.lowercase_ascii _type in
  let uuid = if uuid = "" then Uuidx.to_string (Uuidx.make ()) else uuid in
  (* fill in uuid if none specified *)
  let sr_ref = Ref.make () in
  (* Create SR record in DB *)
  try
    Db.SR.create ~__context ~ref:sr_ref ~uuid ~name_label ~name_description
      ~allowed_operations:[] ~current_operations:[] ~virtual_allocation:0L
      ~physical_utilisation:(-1L) ~physical_size:(-1L) ~content_type ~_type
      ~shared ~other_config:[] ~default_vdi_visibility:true ~sm_config ~blobs:[]
      ~tags:[] ~local_cache_enabled:false ~introduced_by:Ref.null
      ~clustered:false ~is_tools_sr:false ;
    Xapi_sr_operations.update_allowed_operations ~__context ~self:sr_ref ;
    (* Return ref of newly created sr *)
    sr_ref
  with Db_exn.Uniqueness_constraint_violation ("SR", "uuid", _) ->
    raise (Api_errors.Server_error (Api_errors.sr_uuid_exists, [uuid]))

let make ~__context ~host:_ ~device_config:_ ~physical_size:_ ~name_label:_
    ~name_description:_ ~_type ~content_type:_ ~sm_config:_ =
  raise (Api_errors.Server_error (Api_errors.message_deprecated, []))

let get_pbds ~__context ~self ~attached ~master_pos =
  let master = Helpers.get_master ~__context in
  let master_condition = Eq (Field "host", Literal (Ref.string_of master)) in
  let sr_condition = Eq (Field "SR", Literal (Ref.string_of self)) in
  let plugged_condition =
    Eq (Field "currently_attached", Literal (string_of_bool attached))
  in
  let all = List.fold_left (fun acc p -> And (acc, p)) True in
  let master_pbds =
    Db.PBD.get_refs_where ~__context
      ~expr:(all [master_condition; sr_condition; plugged_condition])
  in
  let slave_pbds =
    Db.PBD.get_refs_where ~__context
      ~expr:(all [Not master_condition; sr_condition; plugged_condition])
  in
  match master_pos with
  | `First ->
      master_pbds @ slave_pbds
  | `Last ->
      slave_pbds @ master_pbds

let call_probe ~__context ~host:_ ~device_config ~_type ~sm_config ~f =
  debug "SR.probe sm_config=[ %s ]"
    (String.concat "; " (List.map (fun (k, v) -> k ^ " = " ^ v) sm_config)) ;
  let _type = String.lowercase_ascii _type in
  let queue = !Storage_interface.queue_name ^ "." ^ _type in
  let uri () = Storage_interface.uri () ^ ".d/" ^ _type in
  let rpc = Storage_access.external_rpc queue uri in
  let module Client = Storage_interface.StorageAPI (Idl.Exn.GenClient (struct
    let rpc = rpc
  end)) in
  let dbg = Context.string_of_task __context in
  Storage_utils.transform_storage_exn (fun () ->
      Client.SR.probe dbg queue device_config sm_config |> f
  )

let probe =
  call_probe ~f:(function
    | Storage_interface.Raw x ->
        x
    | Storage_interface.Probe probe_results ->
        (* Here we try to mimic the XML document structure returned in the Raw
           case by SMAPIv1, for backwards-compatibility *)
        let module T = struct
          (** Conveniently output an XML tree using Xmlm *)

          type tree = El of Xmlm.tag * tree list | Data of string

          let data s = Data s

          (** Create an element without a namespace or attributes *)
          let el name children = El ((("", name), []), children)

          let frag = function
            | El (tag, children) ->
                `El (tag, children)
            | Data s ->
                `Data s

          let output_doc ~tree ~output ~dtd =
            Xmlm.output_doc_tree frag output (dtd, tree)
        end in
        let srs =
          probe_results
          (* We return the SRs found by probe *)
          |> List.filter_map (fun r -> r.Storage_interface.sr)
        in
        let sr_info
            Storage_interface.
              {sr_uuid; name_label; name_description; total_space; _} =
          let el_uuid =
            match sr_uuid with
            | Some sr_uuid ->
                [T.el "UUID" [T.data sr_uuid]]
            | None ->
                []
          in
          T.el "SR"
            ([
               T.el "size" [T.data @@ Int64.to_string total_space]
             ; T.el "name_label" [T.data name_label]
             ; T.el "name_description" [T.data name_description]
             ]
            @ el_uuid
            )
        in
        let tree = T.el "SRlist" (List.map sr_info srs) in
        let buf = Buffer.create 20 in
        let output = Xmlm.make_output ~nl:true (`Buffer buf) in
        T.output_doc ~tree ~output ~dtd:None ;
        Buffer.contents buf
    )

let probe_ext =
  let to_xenapi_sr_health =
    let open Storage_interface in
    function
    | Healthy ->
        `healthy
    | Recovering ->
        `recovering
    | Unreachable ->
        `unreachable
    | Unavailable ->
        `unavailable
  in
  let to_xenapi_sr_stat
      Storage_interface.
        {
          sr_uuid
        ; name_label
        ; name_description
        ; total_space
        ; free_space
        ; clustered
        ; health
        } =
    API.
      {
        sr_stat_uuid= sr_uuid
      ; sr_stat_name_label= name_label
      ; sr_stat_name_description= name_description
      ; sr_stat_total_space= total_space
      ; sr_stat_free_space= free_space
      ; sr_stat_clustered= clustered
      ; sr_stat_health= to_xenapi_sr_health health
      }
  in

  let to_xenapi_probe_result
      Storage_interface.{configuration; complete; sr; extra_info} =
    API.
      {
        probe_result_configuration= configuration
      ; probe_result_complete= complete
      ; probe_result_sr= Option.map to_xenapi_sr_stat sr
      ; probe_result_extra_info= extra_info
      }
  in

  call_probe ~f:(function
    | Storage_interface.Raw _ ->
        raise Api_errors.(Server_error (sr_operation_not_supported, []))
    | Storage_interface.Probe results ->
        List.map to_xenapi_probe_result results
    )

(* Create actually makes the SR on disk, and introduces it into db, and creates PBD record for current host *)
let create ~__context ~host ~device_config ~(physical_size : int64) ~name_label
    ~name_description ~_type ~content_type ~shared ~sm_config =
  let pbds, sr_ref =
    Xapi_clustering.with_clustering_lock_if_needed ~__context ~sr_sm_type:_type
      __LOC__ (fun () ->
        Xapi_clustering.assert_cluster_host_is_enabled_for_matching_sms
          ~__context ~host ~sr_sm_type:_type ;
        Helpers.assert_rolling_upgrade_not_in_progress ~__context ;
        debug "SR.create name_label=%s sm_config=[ %s ]" name_label
          (String.concat "; " (List.map (fun (k, v) -> k ^ " = " ^ v) sm_config)) ;
        let sr_uuid = Uuidx.make () in
        let sr_uuid_str = Uuidx.to_string sr_uuid in
        (* Create the SR in the database before creating on disk, so the backends can read the sm_config field. If an error happens here
           	we have to clean up the record.*)
        let sr_ref =
          introduce ~__context ~uuid:sr_uuid_str ~name_label ~name_description
            ~_type ~content_type ~shared ~sm_config
        in
        let pbds =
          if shared then
            let create_on_host host =
              Xapi_pbd.create ~__context ~sR:sr_ref ~device_config ~host
                ~other_config:[]
            in
            let master = Helpers.get_master ~__context in
            let hosts =
              master
              :: List.filter (fun x -> x <> master) (Db.Host.get_all ~__context)
            in
            List.map create_on_host hosts
          else
            [
              Xapi_pbd.create_thishost ~__context ~sR:sr_ref ~device_config
                ~currently_attached:false
            ]
        in
        let device_config =
          try
            Storage_access.create_sr ~__context ~sr:sr_ref ~name_label
              ~name_description ~physical_size
          with e ->
            Db.SR.destroy ~__context ~self:sr_ref ;
            List.iter (fun pbd -> Db.PBD.destroy ~__context ~self:pbd) pbds ;
            raise e
        in
        List.iter
          (fun self ->
            try Db.PBD.set_device_config ~__context ~self ~value:device_config
            with e ->
              warn "Could not set PBD device-config '%s': %s"
                (Db.PBD.get_uuid ~__context ~self)
                (Printexc.to_string e)
          )
          pbds ;
        (pbds, sr_ref)
    )
  in
  Helpers.call_api_functions ~__context (fun rpc session_id ->
      let tasks =
        List.map (fun self -> Client.Async.PBD.plug ~rpc ~session_id ~self) pbds
      in
      Tasks.wait_for_all ~rpc ~session_id ~tasks
  ) ;
  sr_ref

let assert_all_pbds_unplugged ~__context ~sr =
  let pbds = Db.SR.get_PBDs ~__context ~self:sr in
  if
    List.exists
      (fun self -> Db.PBD.get_currently_attached ~__context ~self)
      pbds
  then
    raise (Api_errors.Server_error (Api_errors.sr_has_pbd, [Ref.string_of sr]))

let assert_sr_not_indestructible ~__context ~sr =
  let oc = Db.SR.get_other_config ~__context ~self:sr in
  match List.assoc_opt "indestructible" oc with
  | Some "true" ->
      raise
        (Api_errors.Server_error
           (Api_errors.sr_indestructible, [Ref.string_of sr])
        )
  | _ ->
      ()

let assert_sr_not_local_cache ~__context ~sr =
  let host_with_sr_as_cache =
    Db.Host.get_all ~__context
    |> List.find_opt (fun host ->
           sr = Db.Host.get_local_cache_sr ~__context ~self:host
       )
  in
  match host_with_sr_as_cache with
  | Some host ->
      raise
        (Api_errors.Server_error
           (Api_errors.sr_is_cache_sr, [Ref.string_of host])
        )
  | None ->
      ()

let find_or_create_rrd_vdi ~__context ~sr =
  match
    Db.VDI.get_refs_where ~__context
      ~expr:
        (And
           ( Eq (Field "SR", Literal (Ref.string_of sr))
           , Eq (Field "type", Literal "rrd")
           )
        )
  with
  | [] ->
      let virtual_size = Int64.of_int Xapi_vdi_helpers.VDI_CStruct.vdi_size in
      let vdi =
        Helpers.call_api_functions ~__context (fun rpc session_id ->
            Client.VDI.create ~rpc ~session_id ~name_label:"SR-stats VDI"
              ~name_description:"Disk stores SR-level RRDs" ~sR:sr ~virtual_size
              ~_type:`rrd ~sharable:false ~read_only:false ~other_config:[]
              ~xenstore_data:[] ~sm_config:[] ~tags:[]
        )
      in
      debug "New SR-stats VDI created vdi=%s on sr=%s" (Ref.string_of vdi)
        (Ref.string_of sr) ;
      vdi
  | vdi :: _ ->
      debug "Found existing SR-stats VDI vdi=%s on sr=%s" (Ref.string_of vdi)
        (Ref.string_of sr) ;
      vdi

let should_manage_stats ~__context sr =
  let sr_record = Db.SR.get_record_internal ~__context ~self:sr in
  let sr_features = Xapi_sr_operations.features_of_sr ~__context sr_record in
  Smint.Feature.(has_capability Sr_stats sr_features)
  && Helpers.i_am_srmaster ~__context ~sr

let maybe_push_sr_rrds ~__context ~sr =
  if should_manage_stats ~__context sr then
    let vdi = find_or_create_rrd_vdi ~__context ~sr in
    match Xapi_vdi_helpers.read_raw ~__context ~vdi with
    | None ->
        debug "Stats VDI has no SR RRDs"
    | Some x ->
        let sr_uuid = Db.SR.get_uuid ~__context ~self:sr in
        let tmp_path = Filename.temp_file "push_sr_rrds" ".gz" in
        finally
          (fun () ->
            Unixext.write_string_to_file tmp_path x ;
            Rrdd.push_sr_rrd sr_uuid tmp_path
          )
          (fun () -> Unixext.unlink_safe tmp_path)

let maybe_copy_sr_rrds ~__context ~sr =
  if should_manage_stats ~__context sr then
    let vdi = find_or_create_rrd_vdi ~__context ~sr in
    let sr_uuid = Db.SR.get_uuid ~__context ~self:sr in
    try
      let archive_path = Rrdd.archive_sr_rrd sr_uuid in
      let contents = Unixext.string_of_file archive_path in
      Xapi_vdi_helpers.write_raw ~__context ~vdi ~text:contents
    with Rrd_interface.Rrdd_error (Archive_failed msg) ->
      warn "Archiving of SR RRDs to stats VDI failed: %s" msg

(* CA-325582: Because inactive metrics are kept always loaded in memory and SR
   metrics are stored as host one, we are forced to send an explicit message
   to xcp-rrdd to get the metrics unloaded from memory whenever the SR is
   about to be removed from the database. i.e. just before a destroy or a
   forget. Since all pbds provided by the SR are unplugged at that time there
   are no more metrics about the sr being created, the current ones can be
   deleted. On top of that the metrics should have been archived to disk when
   each PBD got unplugged. *)
let unload_metrics_from_memory ~__context ~sr =
  let short_uuid = String.sub (Db.SR.get_uuid ~__context ~self:sr) 0 8 in
  let is_sr_metric = Astring.String.is_suffix ~affix:short_uuid in
  (* SR data sources are currently stored in memory as host ones.
     Pick the ones that match the short uuid and remove them,
     this prevents these metrics from being archived *)
  Rrdd.query_possible_host_dss ()
  |> List.filter_map (fun ds ->
         if is_sr_metric ds.Data_source.name then
           Some ds.Data_source.name
         else
           None
     )
  |> List.iter (fun ds_name -> Rrdd.forget_host_ds ds_name)

(* Remove SR record from database without attempting to remove SR from disk.
   Assumes all PBDs created from the SR have been unplugged. *)
let really_forget ~__context ~sr =
  let pbds = Db.SR.get_PBDs ~__context ~self:sr in
  let vdis = Db.SR.get_VDIs ~__context ~self:sr in
  List.iter (fun self -> Xapi_pbd.destroy ~__context ~self) pbds ;
  List.iter (fun self -> Db.VDI.destroy ~__context ~self) vdis ;
  Db.SR.destroy ~__context ~self:sr

(* Hijack forget function to be able to unload metrics in slaves
   as well as the master. The actual removal from the database
   can be called in the master directly from the edge of the API,
   in message_forwarding *)
let forget ~__context ~sr = unload_metrics_from_memory ~__context ~sr

(* Remove SR from disk. This operation uses the SR's associated PBD record on
   current host to determine device_config required by SR backend.
   This function does _not_ remove the SR record from the database. *)
let destroy ~__context ~sr =
  let vdis_to_destroy =
    if should_manage_stats ~__context sr then
      [find_or_create_rrd_vdi ~__context ~sr]
    else
      []
  in
  Storage_access.destroy_sr ~__context ~sr ~and_vdis:vdis_to_destroy ;
  let sm_cfg = Db.SR.get_sm_config ~__context ~self:sr in
  Xapi_secret.clean_out_passwds ~__context sm_cfg

let update ~__context ~sr =
  let open Storage_access in
  let task = Context.get_task_id __context in
  let module C = Storage_interface.StorageAPI (Idl.Exn.GenClient (struct
    let rpc = rpc
  end)) in
  Storage_utils.transform_storage_exn (fun () ->
      let sr' =
        Db.SR.get_uuid ~__context ~self:sr |> Storage_interface.Sr.of_string
      in
      let sr_info = C.SR.stat (Ref.string_of task) sr' in
      Db.SR.set_physical_size ~__context ~self:sr ~value:sr_info.total_space ;
      Db.SR.set_physical_utilisation ~__context ~self:sr
        ~value:(Int64.sub sr_info.total_space sr_info.free_space) ;
      Db.SR.set_clustered ~__context ~self:sr ~value:sr_info.clustered ;
      info "%s: updated xapi DB for SR %s" __FUNCTION__
        (Option.fold ~some:Fun.id ~none:sr_info.name_label
           sr_info.Storage_interface.sr_uuid
        )
  )

let get_supported_types ~__context = Sm.supported_drivers ()

module VdiMap = Map.Make (struct
  type t = Storage_interface.Vdi.t

  let compare x y =
    let open Storage_interface.Vdi in
    compare (string_of x) (string_of y)
end)

(* Update VDI records in the database to be in sync with new information
   from a storage backend. *)
let update_vdis ~__context ~sr db_vdis vdi_infos =
  let sr' = sr in
  let open Storage_interface in
  let sr = sr' in
  let db_vdi_map =
    List.fold_left
      (fun m (r, v) -> VdiMap.add (Vdi.of_string v.API.vDI_location) (r, v) m)
      VdiMap.empty db_vdis
  in
  let scan_vdi_map =
    List.fold_left (fun m v -> VdiMap.add v.vdi v m) VdiMap.empty vdi_infos
  in
  let to_delete =
    VdiMap.merge
      (fun _ db scan ->
        match (db, scan) with Some (r, _), None -> Some r | _, _ -> None
      )
      db_vdi_map scan_vdi_map
  in
  let to_create =
    VdiMap.merge
      (fun _ db scan ->
        match (db, scan) with None, Some v -> Some v | _, _ -> None
      )
      db_vdi_map scan_vdi_map
  in
  let find_vdi db_vdi_map loc =
    if VdiMap.mem loc db_vdi_map then
      fst (VdiMap.find loc db_vdi_map)
    else (* CA-254515: Also check for the snapshoted VDI in the database *)
      try
        Db.VDI.get_by_uuid ~__context ~uuid:(Storage_interface.Vdi.string_of loc)
      with _ -> Ref.null
  in
  let get_is_tools_iso vdi =
    List.mem_assoc "xs-tools" vdi.sm_config
    && List.assoc "xs-tools" vdi.sm_config = "true"
  in
  (* Delete ones which have gone away *)
  VdiMap.iter
    (fun _ r ->
      debug "Forgetting VDI: %s" (Ref.string_of r) ;
      Db.VDI.destroy ~__context ~self:r
    )
    to_delete ;
  (* Create the new ones *)
  let db_vdi_map =
    VdiMap.fold
      (fun _ vdi m ->
        let ref = Ref.make () in
        let uuid =
          match Option.bind vdi.uuid Uuidx.of_string with
          | Some x ->
              x
          | None ->
              Uuidx.make ()
        in
        debug "Creating VDI: %s (ref=%s)" (string_of_vdi_info vdi)
          (Ref.string_of ref) ;
        Db.VDI.create ~__context ~ref ~uuid:(Uuidx.to_string uuid)
          ~name_label:vdi.name_label ~name_description:vdi.name_description
          ~current_operations:[] ~allowed_operations:[]
          ~is_a_snapshot:vdi.is_a_snapshot
          ~snapshot_of:(find_vdi db_vdi_map vdi.snapshot_of)
          ~snapshot_time:(Date.of_iso8601 vdi.snapshot_time)
          ~sR:sr ~virtual_size:vdi.virtual_size
          ~physical_utilisation:vdi.physical_utilisation
          ~_type:(try Storage_utils.vdi_type_of_string vdi.ty with _ -> `user)
          ~sharable:vdi.sharable ~read_only:vdi.read_only ~xenstore_data:[]
          ~sm_config:[] ~other_config:[] ~storage_lock:false
          ~location:(Vdi.string_of vdi.vdi) ~managed:true ~missing:false
          ~parent:Ref.null ~tags:[] ~on_boot:`persist ~allow_caching:false
          ~metadata_of_pool:(Ref.of_string vdi.metadata_of_pool)
          ~metadata_latest:false ~is_tools_iso:(get_is_tools_iso vdi)
          ~cbt_enabled:vdi.cbt_enabled ;
        VdiMap.add vdi.vdi (ref, Db.VDI.get_record ~__context ~self:ref) m
      )
      to_create db_vdi_map
  in
  (* Update the ones which already exist, and the ones which were just created
     and may now potentially have null `snapshot_of` references (CA-254515) *)
  let to_update =
    VdiMap.merge
      (fun _ db scan ->
        match (db, scan) with
        | Some (r, v), Some vi ->
            Some (r, v, vi)
        | _, _ ->
            None
      )
      db_vdi_map scan_vdi_map
  in
  VdiMap.iter
    (fun _ (r, v, (vi : vdi_info)) ->
      if v.API.vDI_name_label <> vi.name_label then (
        debug "%s name_label <- %s" (Ref.string_of r) vi.name_label ;
        Db.VDI.set_name_label ~__context ~self:r ~value:vi.name_label
      ) ;
      if v.API.vDI_name_description <> vi.name_description then (
        debug "%s name_description <- %s" (Ref.string_of r) vi.name_description ;
        Db.VDI.set_name_description ~__context ~self:r
          ~value:vi.name_description
      ) ;
      let ty = try Storage_utils.vdi_type_of_string vi.ty with _ -> `user in
      if v.API.vDI_type <> ty then (
        debug "%s type <- %s" (Ref.string_of r) vi.ty ;
        Db.VDI.set_type ~__context ~self:r ~value:ty
      ) ;
      let mop = Ref.of_string vi.metadata_of_pool in
      if v.API.vDI_metadata_of_pool <> mop then (
        debug "%s metadata_of_pool <- %s" (Ref.string_of r) vi.metadata_of_pool ;
        Db.VDI.set_metadata_of_pool ~__context ~self:r ~value:mop
      ) ;
      if v.API.vDI_is_a_snapshot <> vi.is_a_snapshot then (
        debug "%s is_a_snapshot <- %b" (Ref.string_of r) vi.is_a_snapshot ;
        Db.VDI.set_is_a_snapshot ~__context ~self:r ~value:vi.is_a_snapshot
      ) ;
      if v.API.vDI_snapshot_time <> Date.of_iso8601 vi.snapshot_time then (
        debug "%s snapshot_time <- %s" (Ref.string_of r) vi.snapshot_time ;
        Db.VDI.set_snapshot_time ~__context ~self:r
          ~value:(Date.of_iso8601 vi.snapshot_time)
      ) ;
      let snapshot_of = find_vdi db_vdi_map vi.snapshot_of in
      if v.API.vDI_snapshot_of <> snapshot_of then (
        debug "%s snapshot_of <- %s" (Ref.string_of r)
          (Ref.string_of snapshot_of) ;
        Db.VDI.set_snapshot_of ~__context ~self:r ~value:snapshot_of
      ) ;
      if v.API.vDI_read_only <> vi.read_only then (
        debug "%s read_only <- %b" (Ref.string_of r) vi.read_only ;
        Db.VDI.set_read_only ~__context ~self:r ~value:vi.read_only
      ) ;
      if v.API.vDI_virtual_size <> vi.virtual_size then (
        debug "%s virtual_size <- %Ld" (Ref.string_of r) vi.virtual_size ;
        Db.VDI.set_virtual_size ~__context ~self:r ~value:vi.virtual_size
      ) ;
      if v.API.vDI_physical_utilisation <> vi.physical_utilisation then (
        debug "%s physical_utilisation <- %Ld" (Ref.string_of r)
          vi.physical_utilisation ;
        Db.VDI.set_physical_utilisation ~__context ~self:r
          ~value:vi.physical_utilisation
      ) ;
      let is_tools_iso = get_is_tools_iso vi in
      if v.API.vDI_is_tools_iso <> is_tools_iso then (
        debug "%s is_tools_iso <- %b" (Ref.string_of r) is_tools_iso ;
        Db.VDI.set_is_tools_iso ~__context ~self:r ~value:is_tools_iso
      ) ;
      if v.API.vDI_cbt_enabled <> vi.cbt_enabled then (
        debug "%s cbt_enabled <- %b" (Ref.string_of r) vi.cbt_enabled ;
        Db.VDI.set_cbt_enabled ~__context ~self:r ~value:vi.cbt_enabled
      ) ;
      if v.API.vDI_sharable <> vi.sharable then (
        debug "%s sharable <- %b" (Ref.string_of r) vi.sharable ;
        Db.VDI.set_sharable ~__context ~self:r ~value:vi.sharable
      )
    )
    to_update

(* Perform a scan of this locally-attached SR *)
let scan ~__context ~sr =
  let module RefSet = Set.Make (struct
    type t = [`VDI] Ref.t

    let compare = Ref.compare
  end) in
  let open Storage_access in
  let task = Context.get_task_id __context in
  let module C = Storage_interface.StorageAPI (Idl.Exn.GenClient (struct
    let rpc = rpc
  end)) in
  let sr' = Ref.string_of sr in
  SRScanThrottle.execute (fun () ->
      Storage_utils.transform_storage_exn (fun () ->
          let sr_uuid = Db.SR.get_uuid ~__context ~self:sr in
          (* CA-399757: Do not update_vdis unless we are sure that the db was not
             changed during the scan. If it was, retry the scan operation. This
             change might be a result of the SMAPIv1 call back into xapi with
             the db_introduce call, for example.

             Note this still suffers TOCTOU problem, but a complete operation is not easily
             implementable without rearchitecting the storage apis *)
          let rec scan_rec limit =
            let find_vdis () =
              Db.VDI.get_records_where ~__context
                ~expr:(Eq (Field "SR", Literal sr'))
            in
            (* It is sufficient to just compare the refs in two db_vdis, as this
               is what update_vdis uses to determine what to delete *)
            let vdis_ref_equal db_vdi1 db_vdi2 =
              let refs1 = RefSet.of_list (List.map fst db_vdi1) in
              let refs2 = RefSet.of_list (List.map fst db_vdi2) in
              if RefSet.equal refs1 refs2 then
                true
              else
                let log_diff label a b =
                  RefSet.diff a b
                  |> RefSet.elements
                  |> List.map Ref.string_of
                  |> String.concat " "
                  |> debug "%s: VDIs %s during scan: %s" __FUNCTION__ label
                in
                log_diff "removed" refs1 refs2 ;
                log_diff "added" refs2 refs1 ;
                false
            in
            let db_vdis_before = find_vdis () in
            let vs, sr_info =
              C.SR.scan2 (Ref.string_of task)
                (Storage_interface.Sr.of_string sr_uuid)
            in
            let db_vdis_after = find_vdis () in
            if limit > 0 && not (vdis_ref_equal db_vdis_before db_vdis_after)
            then (
              debug "%s detected db change while scanning, retry limit left %d"
                __FUNCTION__ limit ;
              (scan_rec [@tailcall]) (limit - 1)
            ) else if limit = 0 then
              Helpers.internal_error "SR.scan retry limit exceeded"
            else (
              debug "%s no change detected, updating VDIs" __FUNCTION__ ;
              update_vdis ~__context ~sr db_vdis_after vs ;
              let virtual_allocation =
                List.fold_left
                  (fun acc v -> Int64.add v.Storage_interface.virtual_size acc)
                  0L vs
              in
              Db.SR.set_virtual_allocation ~__context ~self:sr
                ~value:virtual_allocation ;
              Db.SR.set_physical_size ~__context ~self:sr
                ~value:sr_info.total_space ;
              Db.SR.set_physical_utilisation ~__context ~self:sr
                ~value:(Int64.sub sr_info.total_space sr_info.free_space) ;
              Db.SR.remove_from_other_config ~__context ~self:sr ~key:"dirty" ;
              Db.SR.set_clustered ~__context ~self:sr ~value:sr_info.clustered
            )
          in
          (* XXX Retry 10 times, and then give up. We should really expect to
             reach this retry limit though, unless something really bad has happened.*)
          scan_rec 10
      )
  )

let set_shared ~__context ~sr ~value =
  if value then (* We can always set an SR to be shared... *)
    Db.SR.set_shared ~__context ~self:sr ~value
  else
    let pbds = Db.PBD.get_all ~__context in
    let pbds =
      List.filter (fun pbd -> Db.PBD.get_SR ~__context ~self:pbd = sr) pbds
    in
    if List.length pbds > 1 then
      raise
        (Api_errors.Server_error
           ( Api_errors.sr_has_multiple_pbds
           , List.map (fun pbd -> Ref.string_of pbd) pbds
           )
        ) ;
    Db.SR.set_shared ~__context ~self:sr ~value

let set_name_label ~__context ~sr ~value =
  let task = Context.get_task_id __context in
  let sr' = Db.SR.get_uuid ~__context ~self:sr in
  let module C = Storage_interface.StorageAPI (Idl.Exn.GenClient (struct
    let rpc = Storage_access.rpc
  end)) in
  Storage_utils.transform_storage_exn (fun () ->
      C.SR.set_name_label (Ref.string_of task)
        (Storage_interface.Sr.of_string sr')
        value
  ) ;
  Db.SR.set_name_label ~__context ~self:sr ~value

let set_name_description ~__context ~sr ~value =
  let task = Context.get_task_id __context in
  let sr' = Db.SR.get_uuid ~__context ~self:sr in
  let module C = Storage_interface.StorageAPI (Idl.Exn.GenClient (struct
    let rpc = Storage_access.rpc
  end)) in
  Storage_utils.transform_storage_exn (fun () ->
      C.SR.set_name_description (Ref.string_of task)
        (Storage_interface.Sr.of_string sr')
        value
  ) ;
  Db.SR.set_name_description ~__context ~self:sr ~value

let set_virtual_allocation ~__context ~self ~value =
  Db.SR.set_virtual_allocation ~__context ~self ~value

let set_physical_size ~__context ~self ~value =
  Db.SR.set_physical_size ~__context ~self ~value

let set_physical_utilisation ~__context ~self ~value =
  Db.SR.set_physical_utilisation ~__context ~self ~value

let assert_can_host_ha_statefile ~__context ~sr =
  let cluster_stack =
    Cluster_stack_constraints.choose_cluster_stack ~__context
  in
  Xha_statefile.assert_sr_can_host_statefile ~__context ~sr ~cluster_stack

let assert_supports_database_replication ~__context ~sr =
  (* Check that each host has a PBD to this SR *)
  let pbds = Db.SR.get_PBDs ~__context ~self:sr in
  let connected_hosts =
    Listext.List.setify
      (List.map (fun self -> Db.PBD.get_host ~__context ~self) pbds)
  in
  let all_hosts = Db.Host.get_all ~__context in
  if List.length connected_hosts < List.length all_hosts then (
    error
      "Cannot enable database replication to SR %s: some hosts lack a PBD: [ \
       %s ]"
      (Ref.string_of sr)
      (String.concat "; "
         (List.map Ref.string_of
            (Listext.List.set_difference all_hosts connected_hosts)
         )
      ) ;
    raise (Api_errors.Server_error (Api_errors.sr_no_pbds, [Ref.string_of sr]))
  ) ;
  (* Check that each PBD is plugged in *)
  List.iter
    (fun self ->
      if not (Db.PBD.get_currently_attached ~__context ~self) then (
        error
          "Cannot enable database replication to SR %s: PBD %s is not plugged"
          (Ref.string_of sr) (Ref.string_of self) ;
        (* Same exception is used in this case (see Helpers.assert_pbd_is_plugged) *)
        raise
          (Api_errors.Server_error (Api_errors.sr_no_pbds, [Ref.string_of sr]))
      )
    )
    pbds ;
  (* Check the exported capabilities of the SR's SM plugin *)
  let srtype = Db.SR.get_type ~__context ~self:sr in
  match
    Db.SM.get_internal_records_where ~__context
      ~expr:(Eq (Field "type", Literal srtype))
  with
  | [] ->
      (* This should never happen because the PBDs are plugged in *)
      Helpers.internal_error "SR does not have corresponding SM record: %s %s"
        (Ref.string_of sr) srtype
  | (_, sm) :: _ ->
      if not (List.mem_assoc "SR_METADATA" sm.Db_actions.sM_features) then
        raise
          (Api_errors.Server_error
             (Api_errors.sr_operation_not_supported, [Ref.string_of sr])
          )

(* Metadata replication to SRs *)
let find_or_create_metadata_vdi ~__context ~sr =
  let pool = Helpers.get_pool ~__context in
  let vdi_can_be_used vdi =
    Db.VDI.get_type ~__context ~self:vdi = `metadata
    && Db.VDI.get_metadata_of_pool ~__context ~self:vdi = pool
    && Db.VDI.get_virtual_size ~__context ~self:vdi >= Redo_log.minimum_vdi_size
  in
  match List.filter vdi_can_be_used (Db.SR.get_VDIs ~__context ~self:sr) with
  | vdi :: _ ->
      (* Found a suitable VDI - try to use it *)
      debug "Using VDI [%s:%s] for metadata replication"
        (Db.VDI.get_name_label ~__context ~self:vdi)
        (Db.VDI.get_uuid ~__context ~self:vdi) ;
      vdi
  | [] ->
      (* Did not find a suitable VDI *)
      debug "Creating a new VDI for metadata replication." ;
      let vdi =
        Helpers.call_api_functions ~__context (fun rpc session_id ->
            Client.VDI.create ~rpc ~session_id ~name_label:"Metadata for DR"
              ~name_description:"Used for disaster recovery" ~sR:sr
              ~virtual_size:Redo_log.minimum_vdi_size ~_type:`metadata
              ~sharable:false ~read_only:false ~other_config:[]
              ~xenstore_data:[] ~sm_config:Redo_log.redo_log_sm_config ~tags:[]
        )
      in
      Db.VDI.set_metadata_latest ~__context ~self:vdi ~value:false ;
      Db.VDI.set_metadata_of_pool ~__context ~self:vdi ~value:pool ;
      (* Call vdi_update to make sure the value of metadata_of_pool is persisted. *)
      Helpers.call_api_functions ~__context (fun rpc session_id ->
          Client.VDI.update ~rpc ~session_id ~vdi
      ) ;
      vdi

let enable_database_replication ~__context ~sr =
  Pool_features.assert_enabled ~__context ~f:Features.DR ;
  assert_supports_database_replication ~__context ~sr ;
  let get_vdi_callback () = find_or_create_metadata_vdi ~__context ~sr in
  Xapi_vdi_helpers.enable_database_replication ~__context ~get_vdi_callback

(* Disable metadata replication to all metadata VDIs in this SR. *)
let disable_database_replication ~__context ~sr =
  let metadata_vdis =
    List.filter
      (fun vdi ->
        Db.VDI.get_type ~__context ~self:vdi = `metadata
        && Db.VDI.get_metadata_of_pool ~__context ~self:vdi
           = Helpers.get_pool ~__context
      )
      (Db.SR.get_VDIs ~__context ~self:sr)
  in
  List.iter
    (fun vdi ->
      Xapi_vdi_helpers.disable_database_replication ~__context ~vdi ;
      (* The VDI may have VBDs hanging around other than those created by the database replication code. *)
      (* They must be destroyed before the VDI can be destroyed. *)
      Xapi_vdi_helpers.destroy_all_vbds ~__context ~vdi ;
      Helpers.call_api_functions ~__context (fun rpc session_id ->
          Client.VDI.destroy ~rpc ~session_id ~self:vdi
      )
    )
    metadata_vdis

let create_new_blob ~__context ~sr ~name ~mime_type ~public =
  let blob = Xapi_blob.create ~__context ~mime_type ~public in
  Db.SR.add_to_blobs ~__context ~self:sr ~key:name ~value:blob ;
  blob

let physical_utilisation_thread ~__context () =
  let module SRMap = Map.Make (struct
    type t = [`SR] Ref.t

    let compare = compare
  end) in
  let sr_cache : bool SRMap.t ref = ref SRMap.empty in
  let srs_to_update () =
    let plugged_srs = Helpers.get_local_plugged_srs ~__context in
    (* Remove SRs that are no longer plugged *)
    sr_cache := SRMap.filter (fun sr _ -> List.mem sr plugged_srs) !sr_cache ;
    (* Cache wether we should manage stats for newly plugged SRs *)
    sr_cache :=
      List.fold_left
        (fun m sr ->
          if SRMap.mem sr m then
            m
          else
            SRMap.add sr (should_manage_stats ~__context sr) m
        )
        !sr_cache plugged_srs ;
    SRMap.(filter (fun _ b -> b) !sr_cache |> bindings) |> List.map fst
  in
  while true do
    Thread.delay 120. ;
    try
      List.iter
        (fun sr ->
          let sr_uuid = Db.SR.get_uuid ~__context ~self:sr in
          try
            let value =
              Rrdd.query_sr_ds sr_uuid "physical_utilisation" |> Int64.of_float
            in
            Db.SR.set_physical_utilisation ~__context ~self:sr ~value
          with Rrd_interface.Rrdd_error (Rrdd_internal_error _) ->
            debug
              "Cannot update physical utilisation for SR %s: RRD unavailable"
              sr_uuid
        )
        (srs_to_update ())
    with e ->
      warn "Exception in SR physical utilisation scanning thread: %s"
        (Printexc.to_string e)
  done

(* APIs for accessing SR level stats *)
let get_data_sources ~__context ~sr =
  List.map Rrdd_helper.to_API_data_source
    (Rrdd.query_possible_sr_dss (Db.SR.get_uuid ~__context ~self:sr))

let record_data_source ~__context ~sr ~data_source =
  Rrdd.add_sr_ds (Db.SR.get_uuid ~__context ~self:sr) data_source

let query_data_source ~__context ~sr ~data_source =
  Rrdd.query_sr_ds (Db.SR.get_uuid ~__context ~self:sr) data_source

let forget_data_source_archives ~__context ~sr ~data_source =
  Rrdd.forget_sr_ds (Db.SR.get_uuid ~__context ~self:sr) data_source

let get_live_hosts ~__context ~sr =
  let choose_fn ~host =
    Xapi_vm_helpers.assert_can_see_specified_SRs ~__context ~reqd_srs:[sr] ~host
  in
  Xapi_vm_helpers.possible_hosts ~__context ~choose_fn ()

let required_api_version_of_sr ~__context ~sr =
  let sr_type = Db.SR.get_type ~__context ~self:sr in
  let expr =
    Xapi_database.Db_filter_types.(Eq (Field "type", Literal sr_type))
  in
  match Db.SM.get_records_where ~__context ~expr with
  | (_, sm) :: _ ->
      Some sm.API.sM_required_api_version
  | [] ->
      warn "Couldn't find SM with type %s" sr_type ;
      None
