(*
   Copyright 2008-2014 Catalin Hritcu, Nikhil Swamy, Microsoft Research and Inria

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*)

module Stlc

type ty =
  | TBool  : ty
  | TArrow : ty -> ty -> ty
  | TPair  : ty -> ty -> ty

let tidbool = TArrow TBool TBool

type exp =
  | EVar   : int -> exp
  | EApp   : exp -> exp -> exp
  | EAbs   : int -> ty -> exp -> exp
  | ETrue  : exp
  | EFalse : exp
  | EIf    : exp -> exp -> exp -> exp
  | EPair  : exp -> exp -> exp
  | EFst   : exp -> exp
  | ESnd   : exp -> exp
  | ELet   : int -> exp -> exp -> exp

let eidbool = EAbs 0 TBool (EVar 0)
let eappidbool = EApp eidbool ETrue
let enot = EAbs 0 TBool (EIf (EVar 0) EFalse ETrue)

val is_value : exp -> Tot bool
let rec is_value e =
  match e with
  | EAbs _ _ _
  | ETrue
  | EFalse      -> true
  | EPair e1 e2 -> is_value e1 && is_value e2
  | _           -> false

let a1 = assert(is_value eidbool)
let a2 = assert(not (is_value eappidbool))

(* Because we only consider call-by-value reduction, we will ever only
   substitute closed values, so this definition of substitution is
   good enough *)
val subst : int -> exp -> exp -> Tot exp
let rec subst x e e' =
  match e' with
  | EVar x' -> if x = x' then e else e'
  | EAbs x' t e1 ->
      EAbs x' t (if x = x' then e1 else (subst x e e1))
  | EApp e1 e2 -> EApp (subst x e e1) (subst x e e2)
  | ETrue -> ETrue
  | EFalse -> EFalse
  | EIf e1 e2 e3 -> EIf (subst x e e1) (subst x e e2) (subst x e e3)
  | EPair e1 e2 -> EPair (subst x e e1) (subst x e e2)
  | EFst e1 -> EFst (subst x e e1)
  | ESnd e1 -> ESnd (subst x e e1)
  | ELet x' e1 e2 -> ELet x' (subst x e e1) (if x = x' then e2 else subst x e e2)

val step : exp -> Tot (option exp)
let rec step e =
  match e with
  | EApp e1 e2 ->
      if is_value e1 then
        if is_value e2 then
          match e1 with
          | EAbs x t e' -> Some (subst x e2 e')
          | _           -> None
        else
          match (step e2) with
          | Some e2' -> Some (EApp e1 e2')
          | None     -> None
      else
        (match (step e1) with
        | Some e1' -> Some (EApp e1' e2)
        | None     -> None)
  | EIf e1 e2 e3 ->
      if is_value e1 then
        match e1 with
        | ETrue   -> Some e2
        | EFalse  -> Some e3
        | _       -> None
      else
        (match (step e1) with
        | Some e1' -> Some (EIf e1' e2 e3)
        | None     -> None)
  | EPair e1 e2 ->
      if is_value e1 then
        if is_value e2 then None
        else
          (match (step e2) with
          | Some e2' -> Some (EPair e1 e2')
          | None     -> None)
      else
        (match (step e1) with
        | Some e1' -> Some (EPair e1' e2)
        | None     -> None)
  | EFst e1 ->
      if is_value e1 then
        (match e1 with
        | EPair v1 v2 -> Some v1
        | _           -> None)
      else
        (match (step e1) with
        | Some e1' -> Some (EFst e1')
        | None     -> None)
  | ESnd e1 ->
      if is_value e1 then
        (match e1 with
        | EPair v1 v2 -> Some v2
        | _           -> None)
      else
        (match (step e1) with
        | Some e1' -> Some (ESnd e1')
        | None     -> None)
  | ELet x e1 e2 ->
      if is_value e1 then Some (subst x e1 e2)
      else
        (match step e1 with
        | Some e1' -> Some (ELet x e1' e2)
        | None     -> None)
  | _ -> None

let a3 = assert (step eappidbool = Some ETrue)
let a4 = assert (step (EApp ETrue ETrue) = None)

type env = int -> Tot (option ty)

val empty : env
let empty _ = None

val extend : env -> int -> ty -> Tot env
let extend g x t x' = if x = x' then Some t else g x'

val typing : env -> exp -> Tot (option ty)
let rec typing g e =
  match e with
  | EVar x -> g x
  | EAbs x t e1 ->
      (match typing (extend g x t) e1 with
      | Some t' -> Some (TArrow t t')
      | None    -> None)
  | EApp e1 e2 ->
      (match typing g e1, typing g e2 with
      | Some (TArrow t11 t12), Some t2 -> if t11 = t2 then Some t12 else None
      | _                    , _       -> None)
  | ETrue
  | EFalse -> Some TBool
  | EIf e1 e2 e3 ->
      (match typing g e1, typing g e2, typing g e3 with
      | Some TBool, Some t2, Some t3 -> if t2 = t3 then Some t2 else None
      | _         , _      , _       -> None)
  | EPair e1 e2 ->
      (match typing g e1, typing g e2 with
      | Some t1, Some t2 -> Some (TPair t1 t2)
      | _      , _       -> None)
  | EFst e1 ->
      (match typing g e1 with
      | Some (TPair t1 t2) -> Some t1
      | _                  -> None)
  | ESnd e1 ->
      (match typing g e1 with
      | Some (TPair t1 t2) -> Some t2
      | _                  -> None)
  | ELet x e1 e2 ->
      (match typing g e1 with
      | Some t -> typing (extend g x t) e2
      | None -> None)

(* These canonical forms lemmas are traditionally used for manual
   progress proofs; they are not used by the automated proof below *)
val canonical_forms_bool : e:exp -> Lemma
      (requires (typing empty e == Some TBool /\ is_value e))
      (ensures (is_ETrue e \/ is_EFalse e))
let canonical_forms_bool e = ()

val canonical_forms_fun : e:exp -> t1:ty -> t2:ty -> Lemma
      (requires (typing empty e == Some (TArrow t1 t2) /\ is_value e))
      (ensures (is_EAbs e))
let canonical_forms_fun e t1 t2 = ()

val progress : e:exp -> Lemma
      (requires (is_Some (typing empty e)))
      (ensures (is_value e \/ (is_Some (step e))))
let rec progress e = using_induction_hyp progress

val appears_free_in : x:int -> e:exp -> Tot bool
let rec appears_free_in x e =
  match e with
  | EVar y -> x = y
  | EApp e1 e2 -> appears_free_in x e1 || appears_free_in x e2
  | EAbs y _ e1 -> x <> y && appears_free_in x e1
  | EIf e1 e2 e3 ->
      appears_free_in x e1 || appears_free_in x e2 || appears_free_in x e3
  | ETrue
  | EFalse -> false (* NS: writing default cases for recursive functions is bad for the solver. TODO: fix CH: Agreed, although in this case it's better not to have a default *)
  | EPair e1 e2 -> appears_free_in x e1 || appears_free_in x e2
  | EFst e1 -> appears_free_in x e1
  | ESnd e1 -> appears_free_in x e1
  | ELet y e1 e2 -> appears_free_in x e1 || (x <> y && appears_free_in x e2)

val free_in_context : x:int -> e:exp -> g:env -> Lemma
      (requires (is_Some (typing g e)))
      (ensures (appears_free_in x e ==> is_Some (g x)))
let rec free_in_context x e g =
  match e with
  | EVar _
  | ETrue
  | EFalse -> ()
  | EAbs y t e1 -> free_in_context x e1 (extend g y t)
  | EApp e1 e2 -> free_in_context x e1 g; free_in_context x e2 g
  | EIf e1 e2 e3 -> free_in_context x e1 g;
                    free_in_context x e2 g; free_in_context x e3 g
  | EPair e1 e2 -> free_in_context x e1 g; free_in_context x e2 g
  | EFst e1 
  | ESnd e1 -> free_in_context x e1 g
  | ELet y e1 e2 ->
      (free_in_context x e1 g;
      free_in_context x e2 (extend g y (Some.v (typing g e1))))

(* I also tried to changed the order of arguments employ
   using_induction_hyp with a partially applied induction
   hypothesis. For some obscure to me reason
   this requires the --full_context_dependency flag even to
   pre-type-check and then it doesn't really help verifying this
   more automatically (left some admits there).
val free_in_context' : g:env -> x:int -> e:exp -> Lemma
      (requires (is_Some (typing g e)))
      (ensures (appears_free_in x e ==> is_Some (g x)))
      [SMTPat (appears_free_in x e); SMTPat (is_Some (typing g e))]
let rec free_in_context' g x e =
  match e with
  | EVar _
  | ETrue
  | EFalse -> ()
  | EAbs y t e1 -> free_in_context' (extend g y t) x e1
  | EApp _ _
  | EIf _ _ _ -> using_induction_hyp (free_in_context' g x); admit()
    (* Tried partially applying free_in_context' to g, but that
       lead to strange error message: expected type U1430 got ...
       Setting the --full_context_dependency fixed this problem. *)
  | EPair _ _
  | EFst _
  | ESnd _ -> using_induction_hyp (free_in_context' g x); admit()
  | ELet y e1 e2 ->
      (free_in_context' g x e1;
      free_in_context' (extend g y (Some.v (typing g e1))) x e2)
*)

(* Corollary of free_in_context when g=empty -- fed to the SMT solver *)
val typable_empty_closed : x:int -> e:exp -> Lemma
      (requires (is_Some (typing empty e)))
      (ensures (not(appears_free_in x e)))
      [SMTPat (appears_free_in x e)]
let typable_empty_closed x e = free_in_context x e empty

opaque logic type Equal (g1:env) (g2:env) =
                 (forall (x:int). g1 x=g2 x)
opaque logic type EqualE (e:exp) (g1:env) (g2:env) =
                 (forall (x:int). appears_free_in x e ==> g1 x=g2 x)

(* Didn't manage to use auto-induction for context_invariance: 
   WARNING: pattern does not contain all quantified variables.
   + Z3 didn't manage to prove easy things automatically.
   Any way we can specify the pattern by hand? What would be a good one here? *)
val context_invariance : e:exp -> g:env -> g':env
                     -> Lemma
                          (requires (EqualE e g g'))
                          (ensures (typing g e == typing g' e))
(* Tried this pattern for the whole lemma
      [SMTPat (EqualE e g g')]
   but got this error:
      Expected type "pattern";
      got type "(_1:(EqualE e g g') -> Tot pattern)"
*)
let rec context_invariance e g g' =
(*  using_induction_hyp context_invariance; *)
  match e with
  | EAbs x t e1 ->
     context_invariance e1 (extend g x t) (extend g' x t)

  | EApp e1 e2 ->
     context_invariance e1 g g';
     context_invariance e2 g g'

  | EIf e1 e2 e3 ->
     context_invariance e1 g g';
     context_invariance e2 g g';
     context_invariance e3 g g'

  | EPair e1 e2 ->
     context_invariance e1 g g';
     context_invariance e2 g g'
 
  | EFst e1
  | ESnd e1 -> context_invariance e1 g g'

  | ELet x e1 e2 ->
     (context_invariance e1 g g';
     match typing g e1 with
     | Some t -> context_invariance e2 (extend g x t) (extend g' x t)
     | None -> ())

  | _ -> ()

val typing_extensional : g:env -> g':env -> e:exp
                      -> Lemma
                           (requires (Equal g g'))
                           (ensures (typing g e == typing g' e))
let typing_extensional g g' e = context_invariance e g g'

val substitution_preserves_typing : x:int -> e:exp -> v:exp ->
      g:env{is_Some (typing empty v) &&
            is_Some (typing (extend g x (Some.v (typing empty v))) e)} ->
      Tot (u:unit{typing g (subst x v e) ==
                  typing (extend g x (Some.v (typing empty v))) e})
let rec substitution_preserves_typing x e v g =
  let Some t_x = typing empty v in
  let gx = extend g x t_x in
  match e with
  | ETrue -> ()
  | EFalse -> ()
  | EVar y ->
     if x=y
     then context_invariance v empty g (* uses lemma typable_empty_closed *)
     else context_invariance e gx g

  | EApp e1 e2 ->
     substitution_preserves_typing x e1 v g;
     substitution_preserves_typing x e2 v g

  | EIf e1 e2 e3 ->
     substitution_preserves_typing x e1 v g;
     substitution_preserves_typing x e2 v g;
     substitution_preserves_typing x e3 v g

  | EAbs y t_y e1 ->
     let gxy = extend gx y t_y in
     let gy = extend g y t_y in
     if x=y
     then typing_extensional gxy gy e1
     else
       (let gyx = extend gy x t_x in
        typing_extensional gxy gyx e1;
        substitution_preserves_typing x e1 v gy)

  | EPair e1 e2 ->
     (substitution_preserves_typing x e1 v g;
      substitution_preserves_typing x e2 v g)

  | EFst e1
  | ESnd e1 ->
      substitution_preserves_typing x e1 v g

  | ELet y e1 e2 ->
     (let Some t1 = typing gx e1 in
     let gxy = extend gx y t1 in
     let gy = extend g y t1 in
     substitution_preserves_typing x e1 v g;
     if x=y then typing_extensional gxy gy e2
     else
       (let gyx = extend gy x t_x in
        typing_extensional gxy gyx e2;
        substitution_preserves_typing x e2 v gy))

val preservation : e:exp{is_Some (typing empty e) /\ is_Some (step e)} ->
      Tot (u:unit{typing empty (Some.v (step e)) == typing empty e})
let rec preservation e =
  match e with
  | EApp e1 e2 ->
     if is_value e1
     then (if is_value e2
           then let EAbs x _ ebody = e1 in
                substitution_preserves_typing x ebody e2 empty
           else preservation e2)
     else preservation e1

  | EIf e1 _ _ ->
      if is_value e1 then ()
      else preservation e1

  | EPair e1 e2 ->
      (match is_value e1, is_value e2 with
      | false, _     -> preservation e1
      | true , false -> preservation e2)

  | EFst e1
  | ESnd e1 ->
      if is_value e1 then ()
      else preservation e1

  | ELet x e1 e2 ->
      (if is_value e1 then substitution_preserves_typing x e2 e1 empty
       else preservation e1)

val typed_step : e:exp{is_Some (typing empty e) /\ not(is_value e)} ->
                 Tot (e':exp{typing empty e' = typing empty e})
let typed_step e = progress e; preservation e; Some.v (step e)

val eval : e:exp{is_Some (typing empty e)} ->
           Dv (v:exp{is_value v && typing empty v = typing empty e})
let rec eval e =
  let Some t = typing empty e in
  match e with
  | EApp e1 e2 ->
     (let EAbs x _ e' = eval e1 in
      let v = eval e2 in
      substitution_preserves_typing x e' v empty;
      eval (subst x v e'))
  | EAbs _ _ _
  | ETrue
  | EFalse     -> e
  | EIf e1 e2 e3 ->
     (match eval e1 with
      | ETrue  -> eval e2
      | EFalse -> eval e3)
  | EPair e1 e2 -> EPair (eval e1) (eval e2)
  | EFst e1 ->
     let EPair v1 _ = eval e1 in v1
  | ESnd e1 ->
     let EPair _ v2 = eval e1 in v2
  | ELet x e1 e2 ->
     (let v = eval e1 in
      substitution_preserves_typing x e2 v empty;
      eval (subst x v e2))
