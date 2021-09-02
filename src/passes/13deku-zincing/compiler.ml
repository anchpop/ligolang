open Trace
open Zinc.Types
module AST = Ast_typed

(* Types defined in ../../stages/6deku-zinc/types.ml *)

type environment = {
  top_level_lets : unit;
  (* not implemented yet, so this is just a placeholder *)
  binders : AST.expression_ Var.t list;
}

let empty_environment = { top_level_lets = (); binders = [] }

let add_binder x = function
  | { top_level_lets; binders } -> { top_level_lets; binders = x :: binders }

let compile_type ~(raise : Errors.zincing_error raise) t =
  t |> Spilling.compile_type ~raise |> fun x -> x.type_content

let rec tail_compile :
    raise:Errors.zincing_error raise -> environment -> AST.expression -> 'a zinc
    =
 fun ~raise environment expr ->
  let () = print_endline (Format.asprintf "tail compile: %a" AST.PP.expression expr) in
  let tail_compile = tail_compile ~raise in
  let other_compile = other_compile ~raise in
  match expr.expression_content with
  | E_lambda lambda ->
      Grab
      ::
      tail_compile
        (environment |> add_binder lambda.binder.wrap_content)
        lambda.result
  | E_let_in let_in ->
      let result_compiled =
        tail_compile
          (environment |> add_binder let_in.let_binder.wrap_content)
          let_in.let_result
      in
      other_compile environment ~k:(Grab :: result_compiled) let_in.rhs
  | _ -> other_compile environment ~k:[ Return ] expr

and other_compile :
    raise:Errors.zincing_error raise ->
    environment ->
    AST.expression ->
    k:'a zinc ->
    'a zinc =
 fun ~raise environment expr ~k ->
  let open AST.Types in
  let () = print_endline (Format.asprintf "other compile: %a" AST.PP.expression expr) in
  let _other_compile = other_compile ~raise in
  let _compile_pattern_matching = compile_pattern_matching ~raise in
  let compile_type = compile_type ~raise in
  (* let compile_function_application = compile_function_application ~raise in *)
  match expr.expression_content with
  | E_literal literal -> (
      match literal with
      | Literal_int x -> Num x :: k
      | Literal_address s -> Address s :: k
      | Literal_bytes b -> Bytes b :: k
      | _ -> failwith "literal type not supported")
  | E_constant constant ->
      let compile_constant c =
        compile_constant ~raise expr.type_expression c :: k
      in
      compile_function_application ~raise ~function_compiler:compile_constant
        environment constant constant.arguments
  | E_variable { wrap_content = var } -> (
      match Utils.find_index var environment.binders with
      | None -> failwith "variable not found in binder!"
      | Some index -> Access index :: k)
  | E_application _application -> failwith "E_application unimplemented"
  | E_lambda _lambda -> failwith "E_lambda unimplemented"
  | E_recursive _recursive -> failwith "E_recursive unimplemented"
  | E_let_in _let_in -> failwith "E_let_in unimplemented"
  | E_type_in _type_in -> failwith "E_type_in unimplemented"
  | E_mod_in _mod_in -> failwith "E_mod_in unimplemented"
  | E_mod_alias _mod_alias -> failwith "E_mod_alias unimplemented"
  | E_raw_code _raw_code -> failwith "E_raw_code unimplemented"
  (* Variant *)
  | E_constructor _constructor ->
      failwith "E_constructor unimplemented" (* For user defined constructors *)
  | E_matching _matching -> failwith "working on pattern matching!"
  (* compile_pattern_matching matching *)
  (* Record *)
  | E_record expression_label_map ->
      let open Zinc.Types in
      let open Stage_common.Types in
      let bindings = LMap.bindings expression_label_map in
      compile_function_application ~raise
        ~function_compiler:(fun z -> MakeRecord z :: k)
        environment
        (List.map
           ~f:(fun (k, value) -> (k, compile_type value.type_expression))
           bindings)
        (List.map ~f:(fun (_, value) -> value) bindings)
  | E_record_accessor _record_accessor ->
      failwith "E_record_accessor unimplemented"
  | E_record_update _record_update -> failwith "E_record_update unimplemented"
  | E_module_accessor _module_access ->
      failwith "E_module_accessor unimplemented"

and compile_constant :
    raise:Errors.zincing_error raise ->
    AST.type_expression ->
    AST.constant ->
    'a zinc_instruction =
 fun ~raise type_expression constant ->
  match constant.cons_name with
  | C_BYTES_UNPACK -> (
      match type_expression.type_content with
      | T_constant
          { injection = Verbatim "option"; parameters = [ unpacking_type ] } ->
          let compiled_type = compile_type ~raise unpacking_type in
          Unpack compiled_type
      | _ ->
          failwith "Incomprehensible type when processing an unpack expression!"
      )
  | C_CHAIN_ID -> Chain_ID
  | name ->
      failwith
        (Format.asprintf "Unsupported constant: %a" AST.PP.constant' name)

and compile_function_application :
      'f.
      raise:Errors.zincing_error raise ->
      function_compiler:('f -> 'a zinc) ->
      environment ->
      'f ->
      AST.expression list ->
      'a zinc_instruction list =
 fun ~raise ~function_compiler environment compiled_func args ->
  let rec comp l =
    match l with
    | [] -> function_compiler compiled_func
    | arg :: args -> other_compile ~raise environment ~k:(comp args) arg
  in
  args |> List.rev |> comp

and compile_pattern_matching :
    raise:Errors.zincing_error raise ->
    compile_function_application:
      (AST.expression -> AST.expression list -> 'a zinc_instruction list) ->
    AST.matching ->
    'a zinc =
 fun ~raise ~compile_function_application:_ to_match ->
  let compile_type = compile_type ~raise in
  let compiled_type = compile_type to_match.matchee.type_expression in
  match (compiled_type, to_match.cases) with
  (* | T_tuple t, Match_record matching_content_record -> compile_function_application to_match.matchee to_match *)
  | _ ->
      failwith
        (Format.asprintf
           "E_matching unimplemented. Need to implement matching for %a"
           Mini_c.PP.type_content
           (compile_type to_match.matchee.type_expression))

let compile_declaration :
    raise:Errors.zincing_error raise -> AST.declaration' -> string * 'a zinc =
 fun ~raise declaration ->
  let () =
    Printf.printf "\nConverting declaration:\n%s\n"
      (Format.asprintf "%a" AST.PP.declaration declaration)
  in
  match declaration with
  | Declaration_constant declaration_constant ->
      let name =
        match declaration_constant.name with
        | Some name -> name
        | None -> failwith "declaration with no name?"
      in
      (name, tail_compile empty_environment ~raise declaration_constant.expr)
  | Declaration_type _declaration_type -> failwith "types not implemented yet"
  | Declaration_module _declaration_module ->
      failwith "modules not implemented yet"
  | Module_alias _module_alias -> failwith "module aliases not implemented yet"

let compile_module :
    raise:Errors.zincing_error raise -> AST.module_fully_typed -> program =
 fun ~raise modul ->
  let (Module_Fully_Typed ast) = modul in
  List.map ast ~f:(fun wrapped ->
      compile_declaration ~raise wrapped.wrap_content)
