%{
(* START HEADER *)

[@@@warning "-42"]

open Simple_utils.Region
module CST = Cst.Cameligo
open CST

(* END HEADER *)
%}

(* See [ParToken.mly] for the definition of tokens. *)

(* Entry points *)

%start contract interactive_expr
%type <CST.t> contract
%type <CST.expr> interactive_expr

                 (*%on_error_reduce nsepseq(selection,DOT)*)

%%

(* RULES *)

(* The rule [sep_or_term(item,sep)] ("separated or terminated list")
   parses a non-empty list of items separated by [sep], and optionally
   terminated by [sep]. *)

sep_or_term_list(item,sep):
  nsepseq(item,sep) {
    $1, None
  }
| nseq(item sep {$1,$2}) {
    let (first,sep), tail = $1 in
    let rec trans (seq, prev_sep as acc) = function
      [] -> acc
    | (item,next_sep)::others ->
        trans ((prev_sep,item)::seq, next_sep) others in
    let list, term = trans ([],sep) tail
    in (first, List.rev list), Some term }

(* Compound constructs *)

par(X):
  "(" X ")" {
    let region = cover $1 $3
    and value  = {lpar=$1; inside=$2; rpar=$3}
    in {region; value} }

(* Sequences

   Series of instances of the same syntactical category have often to
   be parsed, like lists of expressions, patterns etc. The simplest of
   all is the possibly empty sequence (series), parsed below by
   [seq]. The non-empty sequence is parsed by [nseq]. Note that the
   latter returns a pair made of the first parsed item (the parameter
   [X]) and the rest of the sequence (possibly empty). This way, the
   OCaml typechecker can keep track of this information along the
   static control-flow graph. See module [Utils] for the types
   corresponding to the semantic actions of those rules.
 *)

(* Possibly empty sequence of items *)

seq(item):
  (**)           {     [] }
| item seq(item) { $1::$2 }

(* Non-empty sequence of items *)

nseq(item):
  item seq(item) { $1,$2 }

(* Non-empty separated sequence of items *)

nsepseq(item,sep):
  item                       {                        $1, [] }
| item sep nsepseq(item,sep) { let h,t = $3 in $1, ($2,h)::t }

(* Helpers *)

%inline type_name        : "<ident>"  { $1 }
%inline field_name       : "<ident>"  { $1 }
%inline struct_name      : "<ident>"  { $1 }
%inline module_name      : "<constr>" { $1 }

(* Non-empty comma-separated values (at least two values) *)

tuple(item):
  item "," nsepseq(item,",") { let h,t = $3 in $1, ($2,h)::t }

(* Possibly empty semicolon-separated values between brackets *)

list__(item):
  "[" sep_or_term_list(item,";")? "]" {
    let compound = Some (Brackets ($1,$3))
    and region = cover $1 $3 in
    let elements, terminator =
      match $2 with
        None -> None, None
      | Some (elements, terminator) ->
          Some elements, terminator in
    let value = {compound; elements; terminator}
    in {region; value} }

(* Main *)

contract:
  declarations EOF { {decl=$1; eof=$2} }

declarations:
  declaration              { $1,[] : CST.declaration Utils.nseq }
| declaration declarations { Utils.nseq_cons $1 $2              }

declaration:
  type_decl       { TypeDecl $1 }
| let_declaration {      Let $1 }

(* Type declarations *)

type_decl:
  "type" type_name "=" type_expr {
    Scoping.check_reserved_name $2;
    let region = cover $1 (type_expr_to_region $4) in
    let value  = {kwd_type  = $1;
                  name      = $2;
                  eq        = $3;
                  type_expr = $4}
    in {region; value} }

type_expr:
  fun_type | sum_type | record_type { $1 }

fun_type:
  cartesian { $1 }
| cartesian "->" fun_type {
    let start  = type_expr_to_region $1
    and stop   = type_expr_to_region $3 in
    let region = cover start stop in
    TFun {region; value=$1,$2,$3} }

cartesian:
  core_type { $1 }
| core_type "*" nsepseq(core_type,"*") {
    let value  = Utils.nsepseq_cons $1 $2 $3 in
    let region = nsepseq_to_region type_expr_to_region value
    in TProd {region; value} }

core_type:
  type_name      {    TVar $1 }
| "_"            {  TWild  $1 }
| par(type_expr) {    TPar $1 }
| "<string>"     { TString $1 }
| module_name "." type_name {
    let module_name = $1.value in
    let type_name   = $3.value in
    let value       = module_name ^ "." ^ type_name in
    let region      = cover $1.region $3.region
    in TVar {region; value}
  }
| core_type type_name {
    let arg, constr = $1, $2 in
    let start       = type_expr_to_region arg
    and stop        = constr.region in
    let region      = cover start stop in
    let lpar, rpar  = ghost, ghost in
    let value       = {lpar; inside=arg,[]; rpar} in
    let arg         = {region=start; value}
    in TApp {region; value = constr,arg}
  }
| type_tuple type_name {
    let arg, constr = $1, $2 in
    let region = cover arg.region constr.region
    in TApp {region; value = constr,arg} }

type_tuple:
  par(tuple(type_expr)) { $1 }

sum_type:
  ioption("|") nsepseq(variant,"|") {
    Scoping.check_variants (Utils.nsepseq_to_list $2);
    let region = nsepseq_to_region (fun x -> x.region) $2
    in TSum {region; value=$2} }

variant:
  "<constr>" { {$1 with value={constr=$1; arg=None}} }
| "<constr>" "of" fun_type {
    let region = cover $1.region (type_expr_to_region $3)
    and value  = {constr=$1; arg = Some ($2,$3)}
    in {region; value} }

record_type:
  "{" sep_or_term_list(field_decl,";") "}" {
    let ne_elements, terminator = $2 in
    let () = Utils.nsepseq_to_list ne_elements
             |> Scoping.check_fields in
    let region = cover $1 $3
    and value  = {compound = Some (Braces ($1,$3)); ne_elements; terminator}
    in TRecord {region; value} }

field_decl:
  field_name ":" type_expr {
    let stop   = type_expr_to_region $3 in
    let region = cover $1.region stop
    and value  = {field_name=$1; colon=$2; field_type=$3}
    in {region; value} }

(* Top-level definitions *)

let_declaration:
  "let" ioption("rec") let_binding seq(Attr) {
    let kwd_let    = $1 in
    let kwd_rec    = $2 in
    let attributes = $4 in
    let binding    = $3 in
    let value      = kwd_let, kwd_rec, binding, attributes in
    let stop       = expr_to_region binding.let_rhs in
    let region     = cover $1 stop
    in {region; value} }

let_binding:
  "<ident>" nseq(sub_irrefutable) type_annotation? "=" expr {
    Scoping.check_reserved_name $1;
    let binders = Utils.nseq_cons (PVar $1) $2 in
    Utils.nseq_iter Scoping.check_pattern binders;
    {binders; lhs_type=$3; eq=$4; let_rhs=$5}
  }
| irrefutable type_annotation? "=" expr {
    Scoping.check_pattern $1;
    {binders=$1,[]; lhs_type=$2; eq=$3; let_rhs=$4} }

type_annotation:
  ":" type_expr { $1,$2 }

(* Patterns *)

irrefutable:
  sub_irrefutable        { $1 }
| tuple(sub_irrefutable) {
    let region = nsepseq_to_region pattern_to_region $1
    in PTuple {region; value=$1} }

sub_irrefutable:
  "<ident>"                                              {    PVar $1 }
| "_"                                                    {   PWild $1 }
| unit                                                   {   PUnit $1 }
| record_pattern                                         { PRecord $1 }
| par(closed_irrefutable)                                {    PPar $1 }
| "<constr>"         { PConstr (PConstrApp {$1 with value = $1,None}) }

closed_irrefutable:
  irrefutable
| typed_pattern { $1 }
| "<constr>" sub_pattern {
    let stop   = pattern_to_region $2 in
    let region = cover $1.region stop
    and value  = $1, Some $2 in
    PConstr (PConstrApp {region; value}) }

typed_pattern:
  irrefutable ":" type_expr  {
    let start  = pattern_to_region $1 in
    let stop   = type_expr_to_region $3 in
    let region = cover start stop in
    let value  = {pattern=$1; colon=$2; type_expr=$3}
    in PTyped {region; value} }

pattern:
  core_pattern { $1 }
| sub_pattern "::" tail {
    let start  = pattern_to_region $1 in
    let stop   = pattern_to_region $3 in
    let region = cover start stop in
    PList (PCons {region; value=$1,$2,$3})
  }
| tuple(sub_pattern) {
    let region = nsepseq_to_region pattern_to_region $1
    in PTuple {region; value=$1} }

sub_pattern:
  par(tail)    { PPar $1 }
| core_pattern {      $1 }

core_pattern:
  "<ident>"                                    {              PVar $1 }
| "_"                                          {             PWild $1 }
| "<int>"                                      {              PInt $1 }
| "<nat>"                                      {              PNat $1 }
| "<bytes>"                                    {            PBytes $1 }
| "<string>"                                   {           PString $1 }
| "<verbatim>"                                 {         PVerbatim $1 }
| unit                                         {             PUnit $1 }
| par(ptuple)                                  {              PPar $1 }
| list__(tail)                                 { PList (PListComp $1) }
| constr_pattern                               {           PConstr $1 }
| record_pattern                               {           PRecord $1 }

record_pattern:
  "{" sep_or_term_list(field_pattern,";") "}" {
    let ne_elements, terminator = $2 in
    let region = cover $1 $3 in
    let value  = {compound = Some (Braces ($1,$3)); ne_elements; terminator}
    in {region; value} }

field_pattern:
  field_name "=" sub_pattern {
    let start  = $1.region
    and stop   = pattern_to_region $3 in
    let region = cover start stop
    and value  = {field_name=$1; eq=$2; pattern=$3}
    in {region; value} }

constr_pattern:
  "None" { PNone $1 }
| "Some" sub_pattern {
    let stop   = pattern_to_region $2 in
    let region = cover $1 stop
    and value  = $1,$2
    in PSomeApp {region; value}
  }
| "false" { PFalse $1 }
| "true"  {  PTrue $1 }
| "<constr>" {
    PConstrApp {$1 with value=$1,None}
  }
| "<constr>" sub_pattern {
    let region = cover $1.region (pattern_to_region $2)
    in PConstrApp {region; value = $1, Some $2} }

ptuple:
  tuple(tail) {
    let region = nsepseq_to_region pattern_to_region $1
    in PTuple {region; value=$1} }

unit:
  "(" ")" { {region = cover $1 $2; value = ghost, ghost} }

tail:
  sub_pattern { $1 }
| sub_pattern "::" tail {
    let start  = pattern_to_region $1 in
    let stop   = pattern_to_region $3 in
    let region = cover start stop in
    PList (PCons {region; value=$1,$2,$3}) }

(* Expressions *)

interactive_expr:
  expr EOF { $1 }

expr:
  base_cond__open(expr) | match_expr(base_cond) { $1 }

base_cond__open(x):
  base_expr(x) | conditional(x) { $1 }

base_cond:
  base_cond__open(base_cond) { $1 }

base_expr(right_expr):
  tuple_expr
| let_expr(right_expr)
| fun_expr(right_expr)
| disj_expr_level { $1 }

tuple_expr:
  tuple(disj_expr_level) {
    let region = nsepseq_to_region expr_to_region $1
    in ETuple {region; value=$1} }

conditional(right_expr):
  if_then_else(right_expr) | if_then(right_expr) { $1 }

if_then_else(right_expr):
  "if" expr "then" closed_if "else" right_expr {
    let region = cover $1 (expr_to_region $6)
    and value  = {kwd_if   = $1;
                  test     = $2;
                  kwd_then = $3;
                  ifso     = $4;
                  ifnot    = Some($5,$6)}
    in ECond {region; value} }

if_then(right_expr):
  "if" expr "then" right_expr {
    let stop     = expr_to_region $4 in
    let region   = cover $1 stop in
    let value    = {kwd_if   = $1;
                    test     = $2;
                    kwd_then = $3;
                    ifso     = $4;
                    ifnot    = None}
    in ECond {region; value} }

base_if_then_else__open(x):
  base_expr(x) | if_then_else(x) { $1 }

base_if_then_else:
  base_if_then_else__open(base_if_then_else) { $1 }

closed_if:
  base_if_then_else__open(closed_if)
| match_expr(base_if_then_else) { $1 }

match_expr(right_expr):
  "match" expr "with" "|"? cases(right_expr) {
    let cases = {
      value  = Utils.nsepseq_rev $5;
      region = nsepseq_to_region (fun x -> x.region) $5}
    and stop =
      match $5 with
        {region; _}, [] -> region
      |           _, tl -> last fst tl in
    let region = cover $1 stop
    and value  = {kwd_match = $1;
                  expr      = $2;
                  kwd_with  = $3;
                  lead_vbar = $4;
                  cases}
    in ECase {region; value} }

cases(right_expr):
  case_clause(right_expr) {
    let start  = pattern_to_region $1.pattern
    and stop   = expr_to_region $1.rhs in
    let region = cover start stop
    in {region; value=$1}, []
  }
| cases(base_cond) "|" case_clause(right_expr) {
    let start =
      match $1 with
         only_case, [] -> only_case.region
      | _, other_cases -> last fst other_cases
    and stop             = expr_to_region $3.rhs in
    let region           = cover start stop in
    let fst_case         = {region; value=$3}
    and snd_case, others = $1
    in fst_case, ($2,snd_case)::others }

case_clause(right_expr):
  pattern "->" right_expr {
    Scoping.check_pattern $1;
    {pattern=$1; arrow=$2; rhs=$3} }

let_expr(right_expr):
  "let" ioption("rec") let_binding seq(Attr) "in" right_expr  {
    let stop   = expr_to_region $6 in
    let region = cover $1 stop
    and value  = {kwd_let    = $1;
                  kwd_rec    = $2;
                  binding    = $3;
                  attributes = $4;
                  kwd_in     = $5;
                  body       = $6}
    in ELetIn {region; value} }

fun_expr(right_expr):
  "fun" nseq(irrefutable) "->" right_expr {
    let stop   = expr_to_region $4 in
    let region = cover $1 stop in
    let value  = {kwd_fun    = $1;
                  binders    = $2;
                  lhs_type   = None;
                  arrow      = $3;
                  body       = $4}
    in EFun {region; value} }

disj_expr_level:
  bin_op(disj_expr_level, "||", conj_expr_level)
| bin_op(disj_expr_level, "or", conj_expr_level) {
    ELogic (BoolExpr (Or $1)) }
| conj_expr_level { $1 }

bin_op(arg1,op,arg2):
  arg1 op arg2 {
    let start  = expr_to_region $1 in
    let stop   = expr_to_region $3 in
    let region = cover start stop
    and value  = {arg1=$1; op=$2; arg2=$3}
    in {region; value} }

conj_expr_level:
  bin_op(conj_expr_level, "&&", comp_expr_level) {
    ELogic (BoolExpr (And $1)) }
| comp_expr_level { $1 }

comp_expr_level:
  bin_op(comp_expr_level, "<", cat_expr_level) {
    ELogic (CompExpr (Lt $1)) }
| bin_op(comp_expr_level, "<=", cat_expr_level) {
    ELogic (CompExpr (Leq $1)) }
| bin_op(comp_expr_level, ">", cat_expr_level) {
    ELogic (CompExpr (Gt $1)) }
| bin_op(comp_expr_level, ">=", cat_expr_level) {
    ELogic (CompExpr (Geq $1)) }
| bin_op(comp_expr_level, "=", cat_expr_level) {
    ELogic (CompExpr (Equal $1)) }
| bin_op(comp_expr_level, "<>", cat_expr_level) {
    ELogic (CompExpr (Neq $1)) }
| cat_expr_level { $1 }

cat_expr_level:
  bin_op(cons_expr_level, "^", cat_expr_level)     { EString (Cat $1) }
(*| reg(append_expr) {
      bin_op(cons_expr_level, "@", cat_expr_level) { EList (Append $1) } *)
| cons_expr_level                                  {               $1 }

cons_expr_level:
  bin_op(add_expr_level, "::", cons_expr_level)    { EList (ECons $1) }
| add_expr_level                                   {               $1 }

add_expr_level:
  bin_op(add_expr_level, "+", mult_expr_level)     {  EArith (Add $1) }
| bin_op(add_expr_level, "-", mult_expr_level)     {  EArith (Sub $1) }
| mult_expr_level                                  {               $1 }

mult_expr_level:
  bin_op(mult_expr_level, "*", unary_expr_level)   { EArith (Mult $1) }
| bin_op(mult_expr_level, "/", unary_expr_level)   {  EArith (Div $1) }
| bin_op(mult_expr_level, "mod", unary_expr_level) {  EArith (Mod $1) }
| unary_expr_level                                 {               $1 }

unary_expr_level:
  "-" call_expr_level {
    let start = $1 in
    let stop = expr_to_region $2 in
    let region = cover start stop
    and value  = {op=$1; arg=$2}
    in EArith (Neg {region; value})
  }
| "not" call_expr_level {
    let start = $1 in
    let stop = expr_to_region $2 in
    let region = cover start stop
    and value  = {op=$1; arg=$2} in
    ELogic (BoolExpr (Not ({region; value})))
  }
| call_expr_level { $1 }

call_expr_level:
  call_expr | constr_expr | core_expr { $1 }

constr_expr:
  "None" {
    EConstr (ENone $1)
  }
| "Some" core_expr {
    let region = cover $1 (expr_to_region $2)
    in EConstr (ESomeApp {region; value=$1,$2})
  }
| "<constr>" core_expr {
    let region = cover $1.region (expr_to_region $2) in
    EConstr (EConstrApp {region; value=$1, Some $2})
   }
| "<constr>" {
    EConstr (EConstrApp {$1 with value=$1, None}) }

call_expr:
  core_expr nseq(core_expr) {
    let start = expr_to_region $1 in
    let stop = match $2 with
      e, [] -> expr_to_region e
    | _,  l -> last expr_to_region l in
    let region = cover start stop in
    ECall {region; value=$1,$2} }

core_expr:
  "<int>"                             {               EArith (Int $1) }
| "<mutez>"                           {             EArith (Mutez $1) }
| "<nat>"                             {               EArith (Nat $1) }
| "<bytes>"                           {                     EBytes $1 }
| "<ident>" | module_field            {                       EVar $1 }
| projection                          {                      EProj $1 }
| "<string>"                          {           EString (String $1) }
| "<verbatim>"                        {         EString (Verbatim $1) }
| unit                                {                      EUnit $1 }
| "false"                             {  ELogic (BoolExpr (False $1)) }
| "true"                              {  ELogic (BoolExpr (True  $1)) }
| list__(expr)                        {          EList (EListComp $1) }
| sequence                            {                       ESeq $1 }
| record_expr                         {                    ERecord $1 }
| update_record                       {                    EUpdate $1 }
| code_inj                            {                   ECodeInj $1 }
| par(expr)                           {                       EPar $1 }
| par(annot_expr)                     {                     EAnnot $1 }

code_inj:
  "<lang>" expr "]" {
    let region = cover $1.region $3
    and value  = {language=$1; code=$2; rbracket=$3}
    in {region; value} }

annot_expr:
  expr ":" type_expr { $1,$2,$3 }

module_field:
  module_name "." module_fun {
    let region = cover $1.region $3.region in
    {region; value = $1.value ^ "." ^ $3.value} }

module_fun:
  field_name { $1 }
| "or"       { {value="or"; region=$1} }

projection:
  struct_name "." nsepseq(selection,".") {
    let start  = $1.region in
    let stop   = nsepseq_to_region selection_to_region $3 in
    let region = cover start stop in
    let value  = {struct_name=$1; selector=$2; field_path=$3}
    in {region; value}
  }
| module_name "." field_name "." nsepseq(selection,".") {
    let value       = $1.value ^ "." ^ $3.value in
    let struct_name = {$1 with value} in
    let start       = $1.region in
    let stop        = nsepseq_to_region selection_to_region $5 in
    let region      = cover start stop in
    let value       = {struct_name; selector=$4; field_path=$5}
    in {region; value} }

selection:
  field_name { FieldName $1 }
| "<int>"    { Component $1 }

record_expr:
  "{" sep_or_term_list(field_assignment,";") "}" {
    let ne_elements, terminator = $2 in
    let region = cover $1 $3 in
    let value  = {compound = Some (Braces ($1,$3));
                  ne_elements;
                  terminator}
    in {region; value} }

update_record:
  "{" path "with" sep_or_term_list(field_path_assignment,";") "}" {
    let region = cover $1 $5 in
    let ne_elements, terminator = $4 in
    let value = {
      lbrace   = $1;
      record   = $2;
      kwd_with = $3;
      updates  = {value = {compound = None;
                           ne_elements;
                           terminator};
                  region = cover $3 $5};
      rbrace   = $5}
    in {region; value} }

field_path_assignment:
  path "=" expr {
    let region = cover (path_to_region $1) (expr_to_region $3)
    and value  = {field_path=$1; assignment=$2; field_expr=$3}
    in {region; value} }

field_assignment:
  field_name "=" expr {
    let region = cover $1.region (expr_to_region $3)
    and value  = {field_name=$1; assignment=$2; field_expr=$3}
    in {region; value} }

path:
 "<ident>"   { Name $1 }
| projection { Path $1 }

(* Sequences *)

sequence:
  "begin" series? "end" {
    let region   = cover $1 $3
    and compound = Some (BeginEnd ($1,$3)) in
    let elements = $2 in
    let value    = {compound; elements; terminator=None}
    in {region; value} }

series:
  seq_expr ";" series { Utils.nsepseq_cons $1 $2 $3 }
| last_expr           { $1,[] }

last_expr:
  seq_expr
| fun_expr(last_expr)
| match_expr(last_expr)
| let_in_sequence       { $1 }

let_in_sequence:
  "let" ioption("rec") let_binding seq(Attr) "in" series  {
    let seq      = $6 in
    let stop     = nsepseq_to_region expr_to_region seq in
    let region   = cover $1 stop in
    let compound = None in
    let elements = Some seq in
    let value    = {compound; elements; terminator=None} in
    let body     = ESeq {region; value} in
    let value    = {kwd_let    = $1;
                    kwd_rec    = $2;
                    binding    = $3;
                    attributes = $4;
                    kwd_in     = $5;
                    body}
    in ELetIn {region; value} }

seq_expr:
  disj_expr_level | if_then_else (seq_expr) { $1 }
