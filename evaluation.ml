(* 
                         CS 51 Final Project
                         MiniML -- Evaluation
*)

(* This module implements a small untyped ML-like language under
   various operational semantics.
 *)

open Expr ;;
  
(* Exception for evaluator runtime, generated by a runtime error in
   the interpreter *)
exception EvalError of string ;;
  
(* Exception for evaluator runtime, generated by an explicit `raise`
   construct in the object language *)
exception EvalException ;;

(*......................................................................
  Environments and values 
 *)

module type ENV = sig
    (* the type of environments *)
    type env
    (* the type of values stored in environments *)
    type value =
      | Val of expr
      | Closure of (expr * env)
   
    (* empty () -- Returns an empty environment *)
    val empty : unit -> env

    (* close expr env -- Returns a closure for `expr` and its `env` *)
    val close : expr -> env -> value

    (* lookup env varid -- Returns the value in the `env` for the
       `varid`, raising an `Eval_error` if not found *)
    val lookup : env -> varid -> value

    (* extend env varid loc -- Returns a new environment just like
       `env` except that it maps the variable `varid` to the `value`
       stored at `loc`. This allows later changing the value, an
       ability used in the evaluation of `letrec`. To make good on
       this, extending an environment needs to preserve the previous
       bindings in a physical, not just structural, way. *)
    val extend : env -> varid -> value ref -> env

    (* env_to_string env -- Returns a printable string representation
       of environment `env` *)
    val env_to_string : env -> string
                                 
    (* value_to_string ?printenvp value -- Returns a printable string
       representation of a value; the optional flag `printenvp`
       (default: `true`) determines whether to include the environment
       in the string representation when called on a closure *)
    val value_to_string : ?printenvp:bool -> value -> string
  end

module Env : ENV =
  struct
  
    type env = (varid * value ref) list
     and value =
       | Val of expr
       | Closure of (expr * env)

    let empty () : env = [] ;;

    let close (exp : expr) (env : env) : value =
      Closure (exp, env) ;;

    let lookup (env : env) (varname : varid) : value =
      try
        !(List.assoc varname env)
      with
      | Not_found -> raise (EvalError "Not found") ;;

    let extend (env : env) (varname : varid) (loc : value ref) : env =
      (varname, loc) :: (List.remove_assoc varname env) ;;

    let rec value_to_string ?(printenvp : bool = true) (v : value) : string =
      match v with
      | Val exp -> exp_to_concrete_string exp
      | Closure (exp, env) -> 
        if printenvp then env_to_string env ^ exp_to_concrete_string exp
        else exp_to_concrete_string exp

    and env_to_string (env : env) : string =
       match env with
      | [] -> ""
      | hd :: tl ->
        "(" ^ fst hd ^ ", " ^ value_to_string !(snd hd) ^ "); " ^ env_to_string tl ;;

  end
;;


(*......................................................................
  Evaluation functions

  Each of the evaluation functions below evaluates an expression `exp`
  in an environment `env` returning a result of type `value`. We've
  provided an initial implementation for a trivial evaluator, which
  just converts the expression unchanged to a `value` and returns it,
  along with "stub code" for three more evaluators: a substitution
  model evaluator and dynamic and lexical environment model versions.

  Each evaluator is of type `expr -> Env.env -> Env.value` for
  consistency, though some of the evaluators don't need an
  environment, and some will only return values that are "bare
  values" (that is, not closures). 

  DO NOT CHANGE THE TYPE SIGNATURES OF THESE FUNCTIONS. Compilation
  against our unit tests relies on their having these signatures. If
  you want to implement an extension whose evaluator has a different
  signature, implement it as `eval_e` below.  *)

(* The TRIVIAL EVALUATOR, which leaves the expression to be evaluated
   essentially unchanged, just converted to a value for consistency
   with the signature of the evaluators. *)
   
let eval_t (exp : expr) (_env : Env.env) : Env.value =
  (* coerce the expr, unchanged, into a value *)
  Env.Val exp ;;

(* The SUBSTITUTION MODEL evaluator*)

let unop_eval (un : unop) (Env.Val e : Env.value) : Env.value =
  match e with 
  | Num num -> 
    (match un with
    | Negate -> Env.Val (Num (~- num)))
  | Float flo -> 
    (match un with
    | Negate -> Env.Val (Float (~-. flo)))
  | Bool b -> 
    (match un with 
    | Negate -> Env.Val (Bool (not b)))
  | _ -> raise (EvalError "expression of wrong type") ;;

let binop_eval (bi : binop) (Env.Val e : Env.value) (Env.Val ex : Env.value) : Env.value =
  match e, ex with 
  | Num num, Num num1 ->
    (match bi with
    | Plus -> Env.Val (Num ((+) num num1))
    | Minus -> Env.Val (Num ((-) num num1))
    | Times -> Env.Val (Num (( * ) num num1))
    | Divide -> Env.Val (Num ((/) num num1))
    | Equals -> Env.Val (Bool (num = num1))
    | LessThan -> Env.Val (Bool (num < num1))
    | GreaterThan -> Env.Val (Bool (num > num1)))
  | Float flo, Float flo1 -> 
    (match bi with 
    | Plus -> Env.Val (Float ((+.) flo flo1))
    | Minus -> Env.Val (Float ((-.) flo flo1))
    | Times -> Env.Val (Float (( *.) flo flo1))
    | Divide -> Env.Val (Float ((/.) flo flo1))
    | Equals -> Env.Val (Bool (flo = flo1))
    | LessThan -> Env.Val (Bool (flo < flo1))
    | GreaterThan -> Env.Val (Bool (flo > flo1)))
  | Bool b, Bool b1 ->
    (match bi with 
    | Equals -> Env.Val (Bool (b = b1))
    | LessThan -> Env.Val (Bool (b < b1))
    | GreaterThan -> Env.Val (Bool (b > b1))
    | _ -> raise (EvalError "expression of wrong type"))
  | _, _ -> raise (EvalError "expression of wrong type") ;;

let rec eval_s (exp : expr) (env : Env.env) : Env.value =
  match exp with 
  | Var _ -> raise (EvalError "Unbound variable")
  | Num _ | Float _ | Bool _ | Fun _ | Unassigned -> Env.Val exp
  | Unop (un, e) -> unop_eval un (eval_s e env)
  | Binop (bi, e, ex) -> binop_eval bi (eval_s e env) (eval_s ex env) 
  | Conditional (e, ex, exx) ->
    (match eval_s e env with  
    | Env.Val Bool bool -> if bool then eval_s ex env else eval_s exx env 
    | _ -> raise (EvalError "expression expected of type bool")) 
  | Let (x, e, bod) -> 
    (match eval_s e env with 
    | Env.Val v -> eval_s (subst x v bod) env
    | _ -> raise (EvalError "type error")) 
  | Raise -> raise EvalException
  | Letrec (x, e, bod) ->
  (match eval_s e env with
     | Env.Val v ->
       eval_s (subst x (subst x (Letrec (x, v, Var x)) v) bod) env
     | _ -> raise (EvalError "type error"))
  | App (e, bod) ->
    (match eval_s e env, eval_s bod env with
     | Env.Val Fun (x, e1), Env.Val v -> eval_s (subst x v e1) env
     | _ -> raise (EvalError "type error")) ;;

(* The DYNAMICALLY-SCOPED & LEXICALLY-SCOPED ENVIRONMENT MODEL helper evaluator *)

let rec eval_dl_helper (exp : expr) (env : Env.env) (eval : expr -> Env.env -> Env.value) : Env.value =
  match exp with
  | Var v -> Env.lookup env v
  | Num _ | Float _ | Bool _ | Unassigned -> Env.Val exp 
  | Unop (un, e) -> unop_eval un (eval_dl_helper e env eval)
  | Binop (bi, e, ex) -> binop_eval bi (eval_dl_helper e env eval) (eval_dl_helper ex env eval) 
  | Conditional (e, ex, exx) ->
    (match eval_dl_helper e env eval with  
    | Env.Val Bool bool -> if bool then eval_dl_helper ex env eval else eval_dl_helper exx env eval 
    | _ -> raise (EvalError "expression expected of type bool"))
  | Let (v, ex, bod) -> eval_dl_helper bod (Env.extend env v (ref (eval_dl_helper ex env eval))) eval
  | Letrec (v, ex, bod) -> 
    let value = ref (Env.Val Unassigned) in
    let new_env = Env.extend env v value in
      value := eval_dl_helper ex new_env eval;
      eval_dl_helper bod new_env eval
  | Raise -> raise EvalException 
  | _ -> eval exp env ;;

(* The DYNAMICALLY-SCOPED ENVIRONMENT MODEL evaluator *)
   
let rec eval_d (exp : expr) (env : Env.env) : Env.value =
  match exp with
  | Fun _ -> Env.Val exp  
  | App (e, bod) ->
    (match eval_d e env with 
    | Env.Val (Fun (v, ee)) -> 
      (match eval_d bod env with 
       | Env.Val e1 -> eval_d ee (Env.extend env v (ref (Env.Val e1))) 
       | Env.Closure _ -> raise (EvalError "Unexpected closure found"))
       | _ -> raise (EvalError "exp not a fun"))
  | _ -> eval_dl_helper exp env eval_d ;;
       
(* The LEXICALLY-SCOPED ENVIRONMENT MODEL evaluator *)
   
let rec eval_l (exp : expr) (env : Env.env) : Env.value =
  match exp with 
  | Fun (_, _) -> Env.close exp env 
  | App (e, bod) ->
    (match eval_l e env with
    | Env.Closure (Fun (x, e), fun_env) ->
        eval_l e (Env.extend fun_env x (ref (eval_l bod env)))
    | _ -> raise(EvalError "Application by non-function.")) 
  | _ -> eval_dl_helper exp env eval_l ;;
  
(* Connecting the evaluators to the external world. The REPL in
   `miniml.ml` uses a call to the single function `evaluate` defined
   here. Initially, `evaluate` is the trivial evaluator `eval_t`. But
   you can define it to use any of the other evaluators as you proceed
   to implement them. (We will directly unit test the four evaluators
   above, not the `evaluate` function, so it doesn't matter how it's
   set when you submit your solution.) *)
   
let evaluate = eval_l ;;
