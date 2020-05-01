open Core

let pair_map = fun f (x , y) -> (f x , f y)

module Substitution = struct
  module Pattern = struct

    open Trace
    module T = Ast_typed
    (* module TSMap = Trace.TMap(String) *)

    type substs = variable:type_variable -> T.type_content option (* this string is a type_name or type_variable I think *)
    let mk_substs ~v ~expr = (v , expr)

    type 'a w = substs:substs -> 'a -> 'a result

    let rec rec_yes = true
    and s_environment_element_definition ~substs = function
      | T.ED_binder -> ok @@ T.ED_binder
      | T.ED_declaration T.{expr ; free_variables} ->
        let%bind expr = s_expression ~substs expr in
        let%bind free_variables = bind_map_list (s_variable ~substs) free_variables in
        ok @@ T.ED_declaration {expr ; free_variables}
    and s_environment : T.environment w = fun ~substs env ->
      bind_map_list (fun T.{expr_var=variable ; env_elt={ type_value; source_environment; definition }} ->
          let%bind type_value = s_type_expression ~substs type_value in
          let%bind source_environment = s_full_environment ~substs source_environment in
          let%bind definition = s_environment_element_definition ~substs definition in
          ok @@ T.{expr_var=variable ; env_elt={ type_value; source_environment; definition }}) env
    and s_type_environment : T.type_environment w = fun ~substs tenv ->
      bind_map_list (fun T.{type_variable ; type_} ->
        let%bind type_variable = s_type_variable ~substs type_variable in
        let%bind type_ = s_type_expression ~substs type_ in
        ok @@ T.{type_variable ; type_}) tenv
    and s_small_environment : T.small_environment w = fun ~substs T.{expression_environment ; type_environment} ->
      let%bind expression_environment = s_environment ~substs expression_environment in
      let%bind type_environment = s_type_environment ~substs type_environment in
      ok @@ T.{ expression_environment ; type_environment }
    and s_full_environment : T.full_environment w = fun ~substs (a , b) ->
      let%bind a = s_small_environment ~substs a in
      let%bind b = bind_map_list (s_small_environment ~substs) b in
      ok (a , b)

    and s_variable : T.expression_variable w = fun ~substs var ->
      let () = ignore @@ substs in
      ok var

    and s_type_variable : T.type_variable w = fun ~substs tvar ->
      let _TODO = ignore @@ substs in
      Printf.printf "TODO: subst: unimplemented case s_type_variable";
      ok @@ tvar
      (* if String.equal tvar v then
       *   expr
       * else
       *   ok tvar *)
    and s_label : T.label w = fun ~substs l ->
      let () = ignore @@ substs in
      ok l
    
    and s_build_in : T.constant' w = fun ~substs b ->
      let () = ignore @@ substs in
      ok b

    and s_constructor : T.constructor' w = fun ~substs c ->
      let () = ignore @@ substs in
      ok c

    and s_type_name_constant : T.type_constant w = fun ~substs type_name ->
      (* TODO: we don't need to subst anything, right? *)
      let () = ignore @@ substs in
      ok @@ type_name

    and s_type_content : T.type_content w = fun ~substs -> function
        | T.T_sum _ -> failwith "TODO: T_sum"
        | T.T_record _ -> failwith "TODO: T_record"
        | T.T_constant type_name ->
          let%bind type_name = s_type_name_constant ~substs type_name in
          ok @@ T.T_constant (type_name)
        | T.T_variable variable ->
           begin
             match substs ~variable with
             | Some expr -> s_type_content ~substs expr (* TODO: is it the right thing to recursively examine this? We mustn't go into an infinite loop. *)
             | None -> ok @@ T.T_variable variable
           end
        | T.T_operator type_name_and_args ->
          let%bind type_name_and_args = T.Helpers.bind_map_type_operator (s_type_expression ~substs) type_name_and_args in
          ok @@ T.T_operator type_name_and_args
        | T.T_arrow { type1; type2 } ->
           let%bind type1 = s_type_expression ~substs type1 in
           let%bind type2 = s_type_expression ~substs type2 in
           ok @@ T.T_arrow { type1; type2 }

    and s_abstr_type_content : Ast_core.type_content w = fun ~substs -> function
      | Ast_core.T_sum _ -> failwith "TODO: subst: unimplemented case s_type_expression sum"
      | Ast_core.T_record _ -> failwith "TODO: subst: unimplemented case s_type_expression record"
      | Ast_core.T_arrow _ -> failwith "TODO: subst: unimplemented case s_type_expression arrow"
      | Ast_core.T_variable _ -> failwith "TODO: subst: unimplemented case s_type_expression variable"
      | Ast_core.T_operator op ->
         let%bind op =
           Ast_core.bind_map_type_operator
             (s_abstr_type_expression ~substs)
             op in
         (* TODO: when we have generalized operators, we might need to subst the operator name itself? *)
         ok @@ Ast_core.T_operator op
      | Ast_core.T_constant constant ->
         ok @@ Ast_core.T_constant constant

    and s_abstr_type_expression : Ast_core.type_expression w = fun ~substs {type_content;location;type_meta} ->
      let%bind type_content = s_abstr_type_content ~substs type_content in
      ok @@ Ast_core.{type_content;location;type_meta}

    and s_type_expression : T.type_expression w = fun ~substs { type_content; location; type_meta } ->
      let%bind type_content = s_type_content ~substs type_content in
      let%bind type_meta = bind_map_option (s_abstr_type_expression ~substs) type_meta in
      ok @@ T.{ type_content; location; type_meta}
    and s_literal : T.literal w = fun ~substs -> function
      | T.Literal_unit ->
        let () = ignore @@ substs in
        ok @@ T.Literal_unit
      | T.Literal_void ->
        let () = ignore @@ substs in
        ok @@ T.Literal_void
      | (T.Literal_int _ as x)
      | (T.Literal_nat _ as x)
      | (T.Literal_timestamp _ as x)
      | (T.Literal_mutez _ as x)
      | (T.Literal_string _ as x)
      | (T.Literal_bytes _ as x)
      | (T.Literal_address _ as x)
      | (T.Literal_signature _ as x)
      | (T.Literal_key _ as x)
      | (T.Literal_key_hash _ as x)
      | (T.Literal_chain_id _ as x)
      | (T.Literal_operation _ as x) ->
        ok @@ x
    and s_matching_expr : T.matching_expr w = fun ~substs _ ->
      let _TODO = substs in
      failwith "TODO: subst: unimplemented case s_matching"
    and s_accessor  : T.record_accessor w = fun ~substs _ ->
      let _TODO = substs in
      failwith "TODO: subst: unimplemented case s_access_path"

    and s_expression_content : T.expression_content w = fun ~(substs : substs) -> function
      | T.E_literal         x ->
        let%bind x = s_literal ~substs x in
        ok @@ T.E_literal x
      | T.E_constant   {cons_name;arguments} ->
        let%bind cons_name = s_build_in ~substs cons_name in
        let%bind arguments = bind_map_list (s_expression ~substs) arguments in
        ok @@ T.E_constant {cons_name;arguments}
      | T.E_variable        tv ->
        let%bind tv = s_variable ~substs tv in
        ok @@ T.E_variable tv
      | T.E_application {lamb;args} ->
        let%bind lamb = s_expression ~substs lamb in
        let%bind args = s_expression ~substs args in
        ok @@ T.E_application {lamb;args}
      | T.E_lambda          { binder; result } ->
        let%bind binder = s_variable ~substs binder in
        let%bind result = s_expression ~substs result in
        ok @@ T.E_lambda { binder; result }
      | T.E_let_in          { let_binder; rhs; let_result; inline } ->
        let%bind let_binder = s_variable ~substs let_binder in
        let%bind rhs = s_expression ~substs rhs in
        let%bind let_result = s_expression ~substs let_result in
        ok @@ T.E_let_in { let_binder; rhs; let_result; inline }
      | T.E_recursive { fun_name; fun_type; lambda} ->
        let%bind fun_name = s_variable ~substs fun_name in
        let%bind fun_type = s_type_expression ~substs fun_type in
        let%bind sec = s_expression_content ~substs (T.E_lambda lambda) in
        let lambda = match sec with E_lambda l -> l | _ -> failwith "impossible case" in
        ok @@ T.E_recursive { fun_name; fun_type; lambda}
      | T.E_constructor  {constructor;element} ->
        let%bind constructor = s_constructor ~substs constructor in
        let%bind element = s_expression ~substs element in
        ok @@ T.E_constructor {constructor;element}
      | T.E_record          aemap ->
        let _TODO = aemap in
        failwith "TODO: subst in record"
        (* let%bind aemap = TSMap.bind_map_Map (fun ~k:key ~v:val_ ->
         *     let key = s_type_variable ~v ~expr key in
         *     let val_ = s_expression ~v ~expr val_ in
         *     ok @@ (key , val_)) aemap in
         * ok @@ T.E_record aemap *)
      | T.E_record_accessor {record=e;path} ->
        let%bind record = s_expression ~substs e in
        let%bind path = s_label ~substs path in
        ok @@ T.E_record_accessor {record;path}
      | T.E_record_update {record;path;update}->
        let%bind record = s_expression ~substs record in
        let%bind update = s_expression ~substs update in
        ok @@ T.E_record_update {record;path;update}
      | T.E_matching   {matchee;cases} ->
        let%bind matchee = s_expression ~substs matchee in
        let%bind cases = s_matching_expr ~substs cases in
        ok @@ T.E_matching {matchee;cases}

    and s_expression : T.expression w = fun ~(substs:substs) { expression_content; type_expression; environment; location } ->
      let%bind expression_content = s_expression_content ~substs expression_content in
      let%bind type_expr = s_type_expression ~substs type_expression in
      let%bind environment = s_full_environment ~substs environment in
      let location = location in
      ok T.{ expression_content;type_expression=type_expr; environment; location }

    and s_declaration : T.declaration w = fun ~substs ->
      function
        Ast_typed.Declaration_constant {binder ; expr ; inline ; post_env} ->
        let%bind binder = s_variable ~substs binder in
        let%bind expr = s_expression ~substs expr in
        let%bind post_env = s_full_environment ~substs post_env in
        ok @@ Ast_typed.Declaration_constant {binder; expr; inline; post_env}

    and s_declaration_wrap :T.declaration Location.wrap w = fun ~substs d ->
      Trace.bind_map_location (s_declaration ~substs) d    

    (* Replace the type variable ~v with ~expr everywhere within the
       program ~p. TODO: issues with scoping/shadowing. *)
    and s_program : Ast_typed.program w = fun ~substs p ->
      Trace.bind_map_list (s_declaration_wrap ~substs) p

    (*
       Computes `P[v := expr]`.
    *)
    and type_value ~tv ~substs =
      let self tv = type_value ~tv ~substs in
      let (v, expr) = substs in
      match (tv : type_value) with
      | P_variable v' when Var.equal v' v -> expr
      | P_variable _ -> tv
      | P_constant {p_ctor_tag=x ; p_ctor_args=lst} -> (
          let lst' = List.map self lst in
          P_constant {p_ctor_tag=x ; p_ctor_args=lst'}
        )
      | P_apply { tf; targ } -> (
          P_apply { tf = self tf ; targ = self targ }
        )
      | P_forall p -> (
          let aux c = constraint_ ~c ~substs in
          let constraints = List.map aux p.constraints in
          if (p.binder = v) then (
            P_forall { p with constraints }
          ) else (
            let body = self p.body in
            P_forall { p with constraints ; body }
          )
        )

    and constraint_ ~c ~substs =
      match c with
      | C_equation { aval; bval } -> (
        let aux tv = type_value ~tv ~substs in
          C_equation { aval = aux aval ; bval = aux bval }
        )
      | C_typeclass { tc_args; typeclass=tc } -> (
          let tc_args = List.map (fun tv -> type_value ~tv ~substs) tc_args in
          let tc = typeclass ~tc ~substs in
          C_typeclass {tc_args ; typeclass=tc}
        )
      | C_access_label { c_access_label_tval; accessor; c_access_label_tvar } -> (
          let c_access_label_tval = type_value ~tv:c_access_label_tval ~substs in
          C_access_label {c_access_label_tval ; accessor ; c_access_label_tvar}
        )

    and typeclass ~tc ~substs =
      List.map (List.map (fun tv -> type_value ~tv ~substs)) tc

    let program = s_program

    (* Performs beta-reduction at the root of the type *)
    let eval_beta_root ~(tv : type_value) =
      match tv with
        P_apply {tf = P_forall { binder; constraints; body }; targ} ->
        let constraints = List.map (fun c -> constraint_ ~c ~substs:(mk_substs ~v:binder ~expr:targ)) constraints in
        (type_value ~tv:body ~substs:(mk_substs ~v:binder ~expr:targ) , constraints)
      | _ -> (tv , [])
  end

end
