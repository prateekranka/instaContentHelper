-------------------------- MODULE MiraShotPictures --------------------------
EXTENDS Naturals, FiniteSets

CONSTANTS Shots, Cap, TextLimit, LeaseSeconds, TimeoutSeconds, MarginSeconds

VARIABLES state, dispatches, objects, reserved, textActive
vars == <<state, dispatches, objects, reserved, textActive>>

Init ==
    /\ state = [s \in Shots |-> "new"]
    /\ dispatches = [s \in Shots |-> 0]
    /\ objects = {}
    /\ reserved = {}
    /\ textActive = 0

Reserve(s) ==
    /\ state[s] = "new"
    /\ IF Cardinality(reserved) < Cap
       THEN /\ reserved' = reserved \cup {s}
            /\ state' = [state EXCEPT ![s] = "claimed"]
       ELSE /\ UNCHANGED reserved
            /\ state' = [state EXCEPT ![s] = "failed"]
    /\ UNCHANGED <<dispatches, objects, textActive>>

Dispatch(s, remaining) ==
    /\ state[s] = "claimed"
    /\ IF remaining >= TimeoutSeconds + MarginSeconds
       THEN /\ dispatches' = [dispatches EXCEPT ![s] = @ + 1]
            /\ state' = [state EXCEPT ![s] = "running"]
       ELSE /\ UNCHANGED dispatches
            /\ state' = [state EXCEPT ![s] = "failed"]
    /\ UNCHANGED <<objects, reserved, textActive>>

Upload(s) ==
    /\ state[s] = "running" /\ s \notin objects
    /\ objects' = objects \cup {s}
    /\ UNCHANGED <<state, dispatches, reserved, textActive>>

Resolve(s) ==
    /\ state[s] \in {"claimed", "running"}
    /\ state' = [state EXCEPT ![s] = IF s \in objects THEN "ready" ELSE "failed"]
    /\ UNCHANGED <<dispatches, objects, reserved, textActive>>

AdmitText ==
    /\ textActive < TextLimit
    /\ textActive' = textActive + 1
    /\ UNCHANGED <<state, dispatches, objects, reserved>>

CompleteText ==
    /\ textActive > 0
    /\ textActive' = textActive - 1
    /\ UNCHANGED <<state, dispatches, objects, reserved>>

Next ==
    \/ AdmitText \/ CompleteText
    \/ \E s \in Shots :
         \/ Reserve(s) \/ Upload(s) \/ Resolve(s)
         \/ \E remaining \in {LeaseSeconds, TimeoutSeconds + MarginSeconds - 1} : Dispatch(s, remaining)

Spec == Init /\ [][Next]_vars

ReservationsBounded == Cardinality(reserved) <= Cap
DispatchOnce == \A s \in Shots : dispatches[s] <= 1
DispatchNeedsReservation == \A s \in Shots : dispatches[s] > 0 => s \in reserved
ReadyHasObject == \A s \in Shots : state[s] = "ready" => s \in objects
TextSlotsIndependent == (textActive <= TextLimit) /\ (textActive < TextLimit => ENABLED AdmitText)
=============================================================================
