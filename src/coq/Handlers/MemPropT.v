From Coq Require Import
     Strings.String
     ZArith.

From ExtLib Require Import
     Structures.Monad.

From ITree Require Import
     ITree
     Basics.Basics
     Eq.Eq
     Events.StateFacts
     Events.State.

From Vellvm Require Import Error.

From Vellvm.Utils Require Import
     MonadEq1Laws
     PropT
     Raise.

From Vellvm.Semantics Require Import
     MemoryAddress
     LLVMEvents.

Import Basics.Basics.Monads.
Import MonadNotation.
Open Scope monad_scope.

(* Move this ? *)
Definition store_id := N.

Class MonadStoreId (M : Type -> Type) : Type :=
  { fresh_sid : M store_id;
  }.

(* M could use MemState, sid, sid_set, etc... *)
Class StoreIdFreshness (S : Type) : Type :=
  { used_store_id : S -> store_id -> Prop;
    (* fresh_sid : M store_id; *)

    (* run_sid_freshness {A} : M A -> S -> (S * A); *)

    (* (* Doesn't match up with current usage... *)

    (*    E.g., when allocating or writing to memory we call fresh_sid, *)
    (*    then use that to create bytes, and then store those bytes in *)
    (*    memory. The problem is if `used_store_id` is in terms of *)
    (*    `MemState` the laws won't hold until the bytes are actually *)
    (*    stored in `MemState` after the write... *)
    (*  *) *)
    (* fresh_sid_now_used : *)
    (* forall s s' sid, *)
    (*   run_sid_freshness fresh_sid s = (s', sid) -> *)

    (*   (* Was not used *) *)
    (*   forall s'', run_sid_freshness (used_store_id sid) s = (s'', false) /\ *)

    (*   (* Freshly allocated one is now used *) *)
    (*   forall s'', run_sid_freshness (used_store_id sid) s' = (s'', true) /\ *)

    (*   (* Whether other sids are used is preserved *) *)
    (*   forall sid' s'' s''' usedp, *)
    (*     (sid' <> sid -> run_sid_freshness (used_store_id sid') s = (s'', usedp) -> run_sid_freshness (used_store_id sid') s' = (s''', usedp)); *)
  }.

Class AllocationIdFreshness (AllocationId : Type) (S : Type) : Type :=
  { used_allocation_id : S -> AllocationId -> Prop;
  }.

Class ProvenanceFreshness (Provenance : Type) (S : Type) : Type :=
  { used_provenance : S -> Provenance -> Prop;
  }.

Class MonadMemState (MemState : Type) (M : Type -> Type) : Type :=
  { get_mem_state : M MemState;
    put_mem_state : MemState -> M unit;
  }.

Class MemStateMem (MemState : Type) (memory : Type) : Type :=
  { ms_get_memory : MemState -> memory;
    ms_put_memory : memory -> MemState -> MemState;

    ms_get_put_memory : forall ms mem,
      ms_get_memory (ms_put_memory mem ms) = mem;
  }.

Definition modify_mem_state {M MemState} `{Monad M} `{MonadMemState MemState M} (f : MemState -> MemState) : M MemState :=
  ms <- get_mem_state;;
  put_mem_state (f ms);;
  ret ms.

(* TODO: Add RAISE_PICK or something... May need to be in a module *)
Import EitherMonad.
Import Monad.
Import Morphisms.

    (** StateT *)
    (* MemMonad_lift_stateT *)
    (*   {E} `{FailureE -< E} `{UBE -< E} `{OOME -< E} {A} *)
    (*   (ma : M A) : stateT MemState (itree E) A; *)

Definition MemPropT (MemState : Type) (X : Type) : Type
  := MemState -> err_ub_oom (MemState * X)%type -> Prop.

(* Instance MemPropT_Monad : Monad MemPropT. *)
(* Proof. *)
(*   split. *)
(*   - (* ret *) *)
(*     intros T x. *)
(*     unfold MemPropT. *)
(*     intros ms [err_msg | [[ms' res] | oom_msg]]. *)
(*     + exact False. (* error is not a valid behavior here *) *)
(*     + exact (ms = ms' /\ x = res). *)
(*     + exact True. (* Allow OOM to refine anything *) *)
(*   - (* bind *) *)
(*     intros A B ma amb. *)
(*     unfold MemPropT in *. *)

(*     intros ms [err_msg | [[ms'' b] | oom_msg]]. *)
(*     + (* an error is valid when ma errors, or the continuation errors... *) *)
(*       refine *)
(*         ((exists err, ma ms (inl err)) \/ *)
(*          (exists ms' a, *)
(*              ma ms (inr (NoOom (ms', a))) -> *)
(*              (exists err, amb a ms' (inl err)))). *)
(*     + (* No errors, no OOM *) *)
(*       refine *)
(*         (exists ms' a k, *)
(*             ma ms (inr (NoOom (ms', a))) -> *)
(*             amb a ms' (inr (NoOom (ms'', k a)))). *)
(*     + (* OOM is always valid *) *)
(*       exact True. *)
(* Defined. *)

(* To triple check, but the following makes more sense to me *)
Import IdentityMonad.
Instance MemPropT_Monad {MemState : Type} : Monad (MemPropT MemState).
Proof.
  split.
  - (* ret *)
    refine (fun _ v s r =>
              match r with
              | ERR_UB_OOM (mkEitherT (mkEitherT (mkEitherT (mkIdent r)))) =>
                  match r with
                  | inl (OOM_message x) => False
                  | inr (inl (UB_message x)) => False
                  | inr (inr (inl (ERR_message x))) => False
                  | inr (inr (inr (s',r'))) => s' = s /\ r' = v
                  end
              end).
  - (* bind *)
    refine (fun A B ma amb sa r =>
              match r with
              | ERR_UB_OOM (mkEitherT (mkEitherT (mkEitherT (mkIdent r)))) =>
                  match r with
                  | inl (OOM_message x) =>
                      exists msg',
                      (ma sa (raise_oom msg') \/
                         (exists sab a, ma sa (ret (sab, a)) /\
                                     (amb a sab (raise_oom msg'))))
                  | inr (inl (UB_message x)) =>
                      exists msg',
                      (ma sa (raise_ub msg') \/
                         (exists sab a, ma sa (ret (sab, a)) /\
                                     (amb a sab (raise_ub msg'))))
                  | inr (inr (inl (ERR_message x))) =>
                      exists msg',
                      (ma sa (raise_error msg') \/
                         (exists sab a, ma sa (ret (sab, a)) /\
                                     (amb a sab (raise_error msg'))))
                  | inr (inr (inr (s',r'))) =>
                      exists sab a,
                      ma sa (ret (sab, a)) /\
                        amb a sab (ret (s', r'))
                  end
              end).
Defined.

Instance MemPropT_MonadMemState {MemState : Type} : MonadMemState MemState (MemPropT MemState).
Proof.
  (* Operations must actually succeed *)
  split.
  - (* get_mem_state *)
    unfold MemPropT.
    intros ms res.
    destruct res as [[[[[[[oom_res] | [[ub_res] | [[err_res] | [ms' a]]]]]]]]] eqn:Hres.
    + (* OOM *)
      exact False.
    + (* UB *)
      exact False.
    + (* Error *)
      exact False.
    + (* Success *)
      exact (ms = ms' /\ a = ms).
  - (* put_mem_state *)
    unfold MemPropT.
    intros ms_to_put ms res.
    destruct res as [[[[[[[oom_res] | [[ub_res] | [[err_res] | [ms' a]]]]]]]]] eqn:Hres.
    + (* OOM *)
      exact False.
    + (* UB *)
      exact False.
    + (* Error *)
      exact False.
    + exact (ms_to_put = ms').
Defined.

Instance MemPropT_RAISE_OOM {MemState : Type} : RAISE_OOM (MemPropT MemState).
Proof.
  split.
  - intros A msg.
    unfold MemPropT.
    intros ms res.
    destruct res as [[[[[[[oom_res] | [[ub_res] | [[err_res] | [ms' a]]]]]]]]] eqn:Hres.
    + (* OOM *)
      exact True. (* Don't care about particular error message, every OOM allowed. *)
    + (* UB *)
      exact False. (* Must run out of memory, can't UB *)
    + (* Error *)
      exact False. (* Must run out of memory, can't error *)
    + (* Success *)
      exact False. (* Must run out of memory *)
Defined.

Instance MemPropT_RAISE_ERROR {MemState : Type} : RAISE_ERROR (MemPropT MemState).
Proof.
  split.
  - intros A msg.
    unfold MemPropT.
    intros ms res.
    destruct res as [[[[[[[oom_res] | [[ub_res] | [[err_res] | [ms' a]]]]]]]]] eqn:Hres.
    + (* OOM *)
      exact False. (* Must error *)
    + (* UB *)
      exact False. (* Must error *)
    + (* Error *)
      exact True. (* Any error message is good *)
    + (* Success *)
      exact False. (* Must error. *)
Defined.

Instance MemPropT_RAISE_UB {MemState : Type} : RAISE_UB (MemPropT MemState).
Proof.
  split.
  intros A ub_msg.
    intros ms res.
    destruct res as [[[[[[[oom_res] | [[ub_res] | [[err_res] | [ms' a]]]]]]]]] eqn:Hres.
    (* Allow everything because UB *)
    all: exact True.
Defined.

Definition MemPropT_assert {MemState X} (assertion : Prop) : MemPropT MemState X
  := fun ms ms'x =>
       match ms'x with
       | ERR_UB_OOM (mkEitherT (mkEitherT (mkEitherT (mkIdent ms'x)))) =>
           match ms'x with
           | inl (OOM_message x) =>
               assertion
           | inr (inl (UB_message x)) =>
               assertion
           | inr (inr (inl (ERR_message x))) =>
               assertion
           | inr (inr (inr (ms',x))) =>
               ms = ms' /\ assertion
           end
       end.

Definition MemPropT_assert_post {MemState X} (Post : X -> Prop) : MemPropT MemState X
  := fun ms ms'x =>
       match ms'x with
       | ERR_UB_OOM (mkEitherT (mkEitherT (mkEitherT (mkIdent ms'x)))) =>
           match ms'x with
           | inl (OOM_message x) =>
               True
           | inr (inl (UB_message x)) =>
               True
           | inr (inr (inl (ERR_message x))) =>
               True
           | inr (inr (inr (ms',x))) =>
               ms = ms' /\ Post x
           end
       end.

Definition MemPropT_lift_PropT {MemState X} {E} `{UBE -< E} `{OOME -< E} `{FailureE -< E} (m : MemPropT MemState X) : 
  stateT MemState (PropT E) X.
Proof.
  unfold PropT, MemPropT, stateT in *.
  intros ms t.
  specialize (m ms).
  refine (((exists msg, t ≈ raise_ub msg) <-> (forall res, ~ m res)) /\
          ((exists msg, t ≈ raise_error msg) <-> (exists msg, m (raise_error msg))) /\
          ((exists msg, t ≈ raise_oom msg) <-> (exists msg, m (raise_oom msg))) /\
          (forall res, t ≈ ret res <-> m (ret res))).
Defined.

Definition MemPropT_lift_PropT_fresh {MemState X} {E} `{UBE -< E} `{OOME -< E} `{FailureE -< E} (m : MemPropT MemState X) : 
  stateT store_id (stateT MemState (PropT E)) X.
Proof.
  unfold PropT, MemPropT, stateT in *.
  intros sid ms t.
  specialize (m ms).
  refine (((exists msg, t ≈ raise_ub msg) <-> (forall res, ~ m res)) /\
          ((exists msg, t ≈ raise_error msg) <-> (exists msg, m (raise_error msg))) /\
          ((exists msg, t ≈ raise_oom msg) <-> (exists msg, m (raise_oom msg))) /\
          (forall sid ms x, t ≈ ret (ms, (sid, x)) <-> m (ret (ms, x)))).
Defined.
