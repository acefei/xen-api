(*
 * Copyright (C) Cloud Software Group
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

(** [Group] module helps with the classification of different xapi execution
    threads.*)
module Group : sig
  (** Abstract type that represents a group of execution threads in xapi. Each
      group corresponds to a Creator, and has a designated level of priority.*)
  type t

  (** Data structures that represents the identity  *)
  module Identity : sig
    type t

    val root_identity : t

    val make : ?user_agent:string -> string -> t

    val to_string : t -> string
  end

  (** Generic representation of different xapi threads originators. *)
  module Originator : sig
    (** Type that represents different originators of xapi threads. *)
    type t = Internal_SM | Internal_CLI | External

    val of_string : string -> t
    (** [of_string s] creates an originator from a string [s].

        e.g create an originator based on a http header. *)

    val to_string : t -> string
    (** [to_string o] converts an originator [o] to its string representation.*)
  end

  (** Generic representation of different xapi threads origin endpoints. *)
  module Endpoint : sig
    (** Type that represents different origin endpoints of xapi threads. *)
    type t = Internal | External
  end

  (** Generic representation of different xapi threads creators. *)
  module Creator : sig
    (** Abstract type that represents different creators of xapi threads.*)
    type t

    val make :
         ?intrapool:bool
      -> ?endpoint:Endpoint.t
      -> ?identity:Identity.t
      -> ?originator:Originator.t
      -> unit
      -> t
    (** [make o] creates a creator type based on a given originator [o].*)

    val to_string : t -> string
    (** [to_string c] converts a creator [c] to its string representation.*)
  end

  val get_originator : t -> Originator.t
  (** [get_originator group] returns the originator that maps to group [group].*)

  val of_creator : Creator.t -> t
  (** [of_creator c] returns the corresponding group based on the creator [c].*)

  val to_string : t -> string
  (** [to_string g] returns the string representation of the group [g].*)

  val authenticated_root : t
  (** [authenticated_root] represents the main classification of internal xapi
      threads. *)

  val unauthenticated : t
  (** [unauthenticated] represents the classification of xapi threads for
      unauthenticated users. *)
end

(** [Cgroup] module encapsulates different function for managing the cgroups
    corresponding with [Groups].*)
module Cgroup : sig
  (** Represents one of the children of the cgroup directory.*)
  type t = string

  val dir_of : Group.t -> t option
  (** [dir_of group] returns the full path of the cgroup directory corresponding
          to the group [group] as [Some dir].

          Returns [None] if [init dir] has not been called. *)

  val init : string -> unit
  (** [init dir] initializes the hierachy of cgroups associated to all [Group.t]
          types under the directory [dir].*)

  val set_cgroup : Group.Creator.t -> unit
  (** [set_cgroup c] sets the current xapi thread in a cgroup based on the
          creator [c].*)
end

val of_creator : Group.Creator.t -> unit
(** [of_creator g] classifies the current thread based based on the creator [c].*)

val of_req_originator : string option -> unit
(** [of_req_originator o] same as [of_creator] but it classifies based on the
    http request header.*)
