-------------------------- MODULE MiraShotPictures --------------------------
EXTENDS Naturals, FiniteSets

CONSTANTS Shots, Cap, TextLimit, LeaseSeconds, TimeoutSeconds, MarginSeconds, EnforceLateRecovery

VARIABLES state, dispatches, objects, reserved, textActive, checked
vars == <<state, dispatches, objects, reserved, textActive, checked>>

Init ==
    /\ state = [s \in Shots |-> "new"]
    /\ dispatches = [s \in Shots |-> 0]
    /\ objects = {}
    /\ reserved = {}
    /\ textActive = 0
    /\ checked = {}

Reserve(s) ==
    /\ state[s] = "new"
    /\ IF Cardinality(reserved) < Cap
       THEN /\ reserved' = reserved \cup {s}
            /\ state' = [state EXCEPT ![s] = "claimed"]
       ELSE /\ UNCHANGED reserved
            /\ state' = [state EXCEPT ![s] = "failed"]
    /\ UNCHANGED <<dispatches, objects, textActive, checked>>

Dispatch(s, remaining) ==
    /\ state[s] = "claimed"
    /\ IF remaining >= TimeoutSeconds + MarginSeconds
       THEN /\ dispatches' = [dispatches EXCEPT ![s] = @ + 1]
            /\ state' = [state EXCEPT ![s] = "running"]
            /\ UNCHANGED reserved
       ELSE /\ UNCHANGED dispatches
            /\ state' = [state EXCEPT ![s] = "failed"]
            /\ reserved' = reserved \ {s}
    /\ UNCHANGED <<objects, textActive, checked>>

Upload(s) ==
    /\ state[s] \in {"running", "failed"} /\ dispatches[s] > 0 /\ s \notin objects
    /\ objects' = objects \cup {s}
    /\ UNCHANGED <<state, dispatches, reserved, textActive, checked>>

Resolve(s) ==
    /\ state[s] \in {"claimed", "running"}
       \/ (state[s] = "failed" /\ s \in objects /\ s \notin checked)
    /\ state' = [state EXCEPT ![s] =
        IF s \in objects /\ (state[s] # "failed" \/ EnforceLateRecovery)
        THEN "ready" ELSE "failed"]
    /\ checked' = IF s \in objects THEN checked \cup {s} ELSE checked
    /\ reserved' = IF dispatches[s] = 0 THEN reserved \ {s} ELSE reserved
    /\ UNCHANGED <<dispatches, objects, textActive>>

AdmitText ==
    /\ textActive < TextLimit
    /\ textActive' = textActive + 1
    /\ UNCHANGED <<state, dispatches, objects, reserved, checked>>

CompleteText ==
    /\ textActive > 0
    /\ textActive' = textActive - 1
    /\ UNCHANGED <<state, dispatches, objects, reserved, checked>>

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
CheckedObjectIsReady == \A s \in checked : state[s] = "ready"
TextSlotsIndependent == (textActive <= TextLimit) /\ (textActive < TextLimit => ENABLED AdmitText)
=============================================================================
