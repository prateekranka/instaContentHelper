------------------------------ MODULE MiraJobs ------------------------------
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS LeaseSeconds, TimeoutSeconds, MarginSeconds, MaxAttempts,
          EnforceBudget, EnforceTransitions

VARIABLES status, attempts, leaseLeft, retryLeft, started, calls, lostResult, step
vars == <<status, attempts, leaseLeft, retryLeft, started, calls, lostResult, step>>
Attempts == 1..MaxAttempts
ActiveCalls == {a \in Attempts : calls[a] > 0}

Progress ==
    /\ status = "running" /\ started /\ leaseLeft > 0
    /\ step' \in (step + 1)..3
    /\ UNCHANGED <<status, attempts, leaseLeft, retryLeft, started, calls, lostResult>>

Init ==
    /\ status = "queued"
    /\ attempts = 0
    /\ leaseLeft = 0
    /\ retryLeft = 0
    /\ started = FALSE
    /\ calls = [a \in Attempts |-> 0]
    /\ lostResult = FALSE
    /\ step = 0

Claim ==
    /\ status = "queued" \/ (status = "running" /\ leaseLeft = 0)
    /\ attempts < MaxAttempts
    /\ retryLeft = 0
    /\ status' = "running"
    /\ attempts' = attempts + 1
    /\ leaseLeft' = LeaseSeconds
    /\ started' = FALSE
    /\ step' = 0
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
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, lostResult, step>>

Finish(a) ==
    /\ a \in ActiveCalls
    /\ calls' = [calls EXCEPT ![a] = 0]
    /\ status' = IF status = "running" /\ a = attempts THEN "succeeded" ELSE status
    /\ lostResult' = (lostResult \/ a < attempts)
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, step>>

WorkerFailure ==
    /\ status = "running" /\ started
    /\ status' \in (IF attempts < MaxAttempts THEN {"queued", "failed"} ELSE {"failed"})
    /\ calls' = [calls EXCEPT ![attempts] = 0]
    /\ retryLeft' = IF status' = "queued" THEN attempts * 5 ELSE retryLeft
    /\ UNCHANGED <<attempts, leaseLeft, started, lostResult, step>>

Expire ==
    /\ status = "queued" \/ (status = "running" /\ leaseLeft = 0)
    /\ status' = "failed"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult, step>>

Cancel ==
    /\ status \in {"queued", "running"}
    /\ status' = "cancelled"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult, step>>

TryForbiddenUpdate ==
    /\ ~EnforceTransitions
    /\ status = "queued"
    /\ status' = "succeeded"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult, step>>

Decrement(n) == IF n > 0 THEN n - 1 ELSE 0
Tick ==
    /\ leaseLeft > 0 \/ retryLeft > 0 \/ ActiveCalls # {}
    /\ leaseLeft' = Decrement(leaseLeft)
    /\ retryLeft' = Decrement(retryLeft)
    /\ calls' = [a \in Attempts |-> Decrement(calls[a])]
    /\ UNCHANGED <<status, attempts, started, lostResult, step>>

Next ==
    \/ Claim \/ Start \/ \E a \in Attempts : Finish(a)
    \/ WorkerFailure \/ Progress \/ Expire \/ Cancel \/ TryForbiddenUpdate \/ Tick

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

AllowedStep ==
    \/ step' = step
    \/ step' = 0 /\ attempts' = attempts + 1
    \/ /\ step' > step /\ step' <= 3
       /\ status = "running" /\ leaseLeft > 0 /\ started
       /\ UNCHANGED <<status, attempts, leaseLeft, retryLeft, started, calls, lostResult>>

AllowedTransitions == [][AllowedTransition /\ AllowedStep]_vars
=============================================================================
