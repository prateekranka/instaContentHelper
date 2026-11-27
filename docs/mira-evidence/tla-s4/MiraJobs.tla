------------------------------ MODULE MiraJobs ------------------------------
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS LeaseSeconds, TimeoutSeconds, MarginSeconds, MaxAttempts,
          EnforceBudget, EnforceTransitions

VARIABLES status, attempts, leaseLeft, retryLeft, started, calls, lostResult
vars == <<status, attempts, leaseLeft, retryLeft, started, calls, lostResult>>
Attempts == 1..MaxAttempts
ActiveCalls == {a \in Attempts : calls[a] > 0}

Init ==
    /\ status = "queued"
    /\ attempts = 0
    /\ leaseLeft = 0
    /\ retryLeft = 0
    /\ started = FALSE
    /\ calls = [a \in Attempts |-> 0]
    /\ lostResult = FALSE

Claim ==
    /\ status = "queued" \/ (status = "running" /\ leaseLeft = 0)
    /\ attempts < MaxAttempts
    /\ retryLeft = 0
    /\ status' = "running"
    /\ attempts' = attempts + 1
    /\ leaseLeft' = LeaseSeconds
    /\ started' = FALSE
    /\ UNCHANGED <<retryLeft, calls, lostResult>>

Start ==
    /\ status = "running"
    /\ ~started /\ leaseLeft > 0
    /\ IF ~EnforceBudget \/ leaseLeft >= TimeoutSeconds + MarginSeconds
       THEN /\ calls' = [calls EXCEPT ![attempts] = TimeoutSeconds]
            /\ started' = TRUE
            /\ UNCHANGED status
       ELSE /\ status' = "failed"
            /\ UNCHANGED <<started, calls>>
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, lostResult>>

Finish(a) ==
    /\ a \in ActiveCalls
    /\ calls' = [calls EXCEPT ![a] = 0]
    /\ status' = IF status = "running" /\ a = attempts THEN "succeeded" ELSE status
    /\ lostResult' = (lostResult \/ a < attempts)
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started>>

WorkerFailure ==
    /\ status = "running" /\ started
    /\ status' \in (IF attempts < MaxAttempts THEN {"queued", "failed"} ELSE {"failed"})
    /\ calls' = [calls EXCEPT ![attempts] = 0]
    /\ retryLeft' = IF status' = "queued" THEN attempts * 5 ELSE retryLeft
    /\ UNCHANGED <<attempts, leaseLeft, started, lostResult>>

Expire ==
    /\ status = "queued" \/ (status = "running" /\ leaseLeft = 0)
    /\ status' = "failed"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult>>

Cancel ==
    /\ status \in {"queued", "running"}
    /\ status' = "cancelled"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult>>

TryForbiddenUpdate ==
    /\ ~EnforceTransitions
    /\ status = "queued"
    /\ status' = "succeeded"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult>>

Decrement(n) == IF n > 0 THEN n - 1 ELSE 0
Tick ==
    /\ leaseLeft > 0 \/ retryLeft > 0 \/ ActiveCalls # {}
    /\ leaseLeft' = Decrement(leaseLeft)
    /\ retryLeft' = Decrement(retryLeft)
    /\ calls' = [a \in Attempts |-> Decrement(calls[a])]
    /\ UNCHANGED <<status, attempts, started, lostResult>>

Next ==
    \/ Claim \/ Start \/ \E a \in Attempts : Finish(a)
    \/ WorkerFailure \/ Expire \/ Cancel \/ TryForbiddenUpdate \/ Tick

Spec == Init /\ [][Next]_vars

LeaseCoversCall ==
    \A a \in ActiveCalls : a = attempts /\ leaseLeft >= calls[a] + MarginSeconds
NoOverlap == Cardinality(ActiveCalls) <= 1
NoLostResult == ~lostResult

AllowedTransition ==
    \/ /\ status' = status /\ attempts' = attempts /\ leaseLeft' <= leaseLeft
    \/ /\ status' = "running"
       /\ status = "queued" \/ (status = "running" /\ leaseLeft = 0)
       /\ retryLeft = 0 /\ attempts < MaxAttempts
       /\ attempts' = attempts + 1 /\ leaseLeft' > 0
    \/ /\ status' \in {"succeeded", "failed", "cancelled"}
       /\ status = "running" \/ (status = "queued" /\ status' # "succeeded")
       /\ attempts' = attempts /\ leaseLeft' = leaseLeft
    \/ /\ status = "running" /\ status' = "queued" /\ attempts < MaxAttempts
       /\ attempts' = attempts /\ leaseLeft' = leaseLeft

AllowedTransitions == [][AllowedTransition]_vars
=============================================================================
