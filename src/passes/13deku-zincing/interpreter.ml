open Zinc.Types

type env_item =
  [ `Z of zinc_instruction | `Clos of clos | `Record of stack_item list ]
[@@deriving show, eq]

and stack_item =
  [ (* copied from env_item *)
    `Z of zinc_instruction
  | `Clos of clos
  | `Record of stack_item list
  | (* marker to note function calls *)
    `Marker of zinc * env_item list ]
[@@deriving show, eq]

and clos = { code : zinc; env : env_item list } [@@deriving show, eq]

type env = env_item list [@@deriving show, eq]

type stack = stack_item list [@@deriving show, eq]

let env_to_stack : env_item -> stack_item = function #env_item as x -> x

let initial_state ?initial_stack:(stack = []) a = (a, [], stack)

let rec apply_zinc (instructions, env, stack) =
  let apply_once (instructions : zinc) (env : env_item list)
      (stack : stack_item list) =
    match (instructions, env, stack) with
    | Grab :: c, env, `Z v :: s -> Some (c, `Z v :: env, s)
    | Grab :: c, env, `Clos v :: s -> Some (c, `Clos v :: env, s)
    | Grab :: c, env, `Marker (c', e') :: s ->
        Some (c', e', `Clos { code = Grab :: c; env } :: s)
    | Return :: _, _, `Z v :: `Marker (c', e') :: s -> Some (c', e', `Z v :: s)
    | Return :: _, _, `Clos { code = c'; env = e' } :: s -> Some (c', e', s)
    | PushRetAddr c' :: c, env, s -> Some (c, env, `Marker (c', env) :: s)
    | Apply :: _, _, `Clos { code = c'; env = e' } :: s -> Some (c', e', s)
    (* Below here is just modern SECD *)
    | Access n :: c, env, s -> (
        let nth = List.nth env n in
        match nth with
        | Some nth -> Some (c, env, (nth |> env_to_stack) :: s)
        | None -> None)
    | Closure c' :: c, env, s -> Some (c, env, `Clos { code = c'; env } :: s)
    | EndLet :: c, _ :: env, s -> Some (c, env, s)
    (* zinc extensions *)
    (* operations that jsut drop something on the stack haha *)
    | ((Num _ | Address _) as v) :: c, env, s -> Some (c, env, `Z v :: s)
    (* ADTs *)
    | MakeRecord r :: c, env, s ->
        let rec split n a =
          match (n, a) with
          | 0, a -> ([], a)
          | n, x :: xs ->
              let first, rest = split (n - 1) xs in
              (x :: first, rest)
          | _, _ ->
              failwith
                "can't split a list at a point greater than that list's length"
        in
        let record_items, new_stack = split (List.length r) s in

        Some (c, env, `Record record_items :: new_stack)
    (* Math *)
    | Succ :: c, env, `Z (Num i) :: s ->
        Some (c, env, `Z (Num (Z.add i Z.one)) :: s)
    (* Tezos specific *)
    | ChainID :: c, env, s -> Some (c, env, `Z (Hash "chain id hash here!") :: s)
    (* should be unreachable except when program is done *)
    | (Return | Grab) :: _, _, _ -> None
    | x :: _, _, _ ->
        failwith (Format.asprintf "%a unimplemented!" pp_zinc_instruction x)
    | _ ->
        failwith
          (Format.asprintf "ran out of instructions without hitting return!")
  in
  match apply_once instructions env stack with
  | None -> (instructions, env, stack)
  | Some (instructions, env, stack) -> apply_zinc (instructions, env, stack)
