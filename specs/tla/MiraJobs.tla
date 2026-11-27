------------------------------ MODULE MiraJobs ------------------------------
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS LeaseSeconds, TimeoutSeconds, MarginSeconds, MaxAttempts,
          EnforceBudget, EnforceTransitions, EnforceEarlyStop, EnforceSaveOnce

VARIABLES status, attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
          stoppedBeforeStart, resultAttempt, staged
vars == <<status, attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
          stoppedBeforeStart, resultAttempt, staged>>
Attempts == 1..MaxAttempts
ActiveCalls == {a \in Attempts : calls[a] > 0}

Progress ==
    /\ status = "running" /\ started /\ leaseLeft > 0
    /\ step' \in (step + 1)..3
    /\ UNCHANGED <<status, attempts, leaseLeft, retryLeft, started, calls, lostResult, stoppedBeforeStart, resultAttempt, staged>>

Init ==
    /\ status = "absent"
    /\ attempts = 0
    /\ leaseLeft = 0
    /\ retryLeft = 0
    /\ started = FALSE
    /\ calls = [a \in Attempts |-> 0]
    /\ lostResult = FALSE
    /\ step = 0
    /\ stoppedBeforeStart = FALSE
    /\ resultAttempt = 0
    /\ staged = FALSE

Admit ==
    /\ status = "absent"
    /\ ~stoppedBeforeStart \/ ~EnforceEarlyStop
    /\ status' = "queued"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
                    stoppedBeforeStart, resultAttempt, staged>>

StopBeforeStart ==
    /\ status = "absent" /\ ~stoppedBeforeStart
    /\ stoppedBeforeStart' = TRUE
    /\ UNCHANGED <<status, attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
                    resultAttempt, staged>>

Claim ==
    /\ status = "queued" \/ (status = "running" /\ leaseLeft = 0 /\ (~started \/ ~EnforceBudget))
    /\ attempts < MaxAttempts
    /\ retryLeft = 0
    /\ status' = "running"
    /\ attempts' = attempts + 1
    /\ leaseLeft' = LeaseSeconds
    /\ started' = FALSE
    /\ step' = 0
    /\ UNCHANGED <<retryLeft, calls, lostResult, stoppedBeforeStart, resultAttempt, staged>>

Start ==
    /\ status = "running"
    /\ ~started /\ leaseLeft > 0
    /\ IF ~EnforceBudget \/ leaseLeft >= TimeoutSeconds + MarginSeconds
       THEN /\ calls' = [calls EXCEPT ![attempts] = TimeoutSeconds]
            /\ started' = TRUE
            /\ UNCHANGED status
       ELSE /\ status' = "failed"
            /\ UNCHANGED <<started, calls>>
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, lostResult, step, stoppedBeforeStart, resultAttempt, staged>>

Finish(a) ==
    /\ a \in ActiveCalls
    /\ calls' = [calls EXCEPT ![a] = 0]
    /\ resultAttempt' = IF status = "running" /\ a = attempts /\ resultAttempt = 0
                         THEN a ELSE resultAttempt
    /\ lostResult' = (lostResult \/ a < attempts)
    /\ UNCHANGED <<status, attempts, leaseLeft, retryLeft, started, step, stoppedBeforeStart, staged>>

Stage ==
    /\ status = "running" /\ resultAttempt = attempts /\ resultAttempt > 0 /\ ~staged
    /\ staged' = TRUE
    /\ UNCHANGED <<status, attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
                    stoppedBeforeStart, resultAttempt>>

Complete ==
    /\ status = "running" /\ staged
    /\ status' = "succeeded"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
                    stoppedBeforeStart, resultAttempt, staged>>

SaveFailure ==
    /\ ~EnforceSaveOnce
    /\ status = "running" /\ resultAttempt = attempts /\ resultAttempt > 0 /\ attempts < MaxAttempts
    /\ status' = "queued"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
                    stoppedBeforeStart, resultAttempt, staged>>

WorkerFailure ==
    /\ status = "running" /\ started /\ resultAttempt = 0
    /\ status' \in (IF attempts < MaxAttempts THEN {"queued", "failed"} ELSE {"failed"})
    /\ calls' = [calls EXCEPT ![attempts] = 0]
    /\ retryLeft' = IF status' = "queued" THEN attempts * 5 ELSE retryLeft
    /\ UNCHANGED <<attempts, leaseLeft, started, lostResult, step, stoppedBeforeStart, resultAttempt, staged>>

Expire ==
    /\ status = "queued" \/ (status = "running" /\ leaseLeft = 0)
    /\ ~staged
    /\ status' = "failed"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
                    stoppedBeforeStart, resultAttempt, staged>>

Cancel ==
    /\ status \in {"queued", "running"}
    /\ status' = "cancelled"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
                    stoppedBeforeStart, resultAttempt, staged>>

TryForbiddenUpdate ==
    /\ ~EnforceTransitions
    /\ status = "queued"
    /\ status' = "succeeded"
    /\ UNCHANGED <<attempts, leaseLeft, retryLeft, started, calls, lostResult, step,
                    stoppedBeforeStart, resultAttempt, staged>>

Decrement(n) == IF n > 0 THEN n - 1 ELSE 0
Tick ==
    /\ leaseLeft > 0 \/ retryLeft > 0 \/ ActiveCalls # {}
    /\ leaseLeft' = Decrement(leaseLeft)
    /\ retryLeft' = Decrement(retryLeft)
    /\ calls' = [a \in Attempts |-> Decrement(calls[a])]
    /\ UNCHANGED <<status, attempts, started, lostResult, step, stoppedBeforeStart, resultAttempt, staged>>

Next ==
    \/ Admit \/ StopBeforeStart \/ Claim \/ Start \/ (\E a \in Attempts : Finish(a))
    \/ Stage \/ Complete \/ SaveFailure
    \/ WorkerFailure \/ Progress \/ Expire \/ Cancel \/ TryForbiddenUpdate \/ Tick

Spec == Init /\ [][Next]_vars

LeaseCoversCall ==
    \A a \in ActiveCalls : a = attempts /\ leaseLeft >= calls[a] + MarginSeconds
NoOverlap == Cardinality(ActiveCalls) <= 1
NoLostResult == ~lostResult
StoppedBeforeStartNeverClaims == stoppedBeforeStart => attempts = 0
ResultNotRegenerated == resultAttempt = 0 \/ attempts = resultAttempt
SuccessHasResult == status = "succeeded" => staged

AllowedTransition ==
    \/ /\ status' = status /\ attempts' = attempts /\ leaseLeft' <= leaseLeft
    \/ /\ status = "absent" /\ status' = "queued" /\ attempts' = attempts
    \/ /\ status' = "running"
       /\ status = "queued" \/ (status = "running" /\ leaseLeft = 0)
       /\ retryLeft = 0 /\ attempts < MaxAttempts
       /\ attempts' = attempts + 1 /\ leaseLeft' > 0
    \/ /\ status' \in {"succeeded", "failed", "cancelled"}
       /\ status = "running" \/ (status = "queued" /\ status' # "succeeded")
       /\ attempts' = attempts /\ leaseLeft' = leaseLeft
       /\ (status' = "succeeded" => staged)
    \/ /\ status = "running" /\ status' = "queued" /\ attempts < MaxAttempts
       /\ attempts' = attempts /\ leaseLeft' = leaseLeft

AllowedStep ==
    \/ step' = step
    \/ step' = 0 /\ attempts' = attempts + 1
    \/ /\ step' > step /\ step' <= 3
       /\ status = "running" /\ leaseLeft > 0 /\ started
       /\ UNCHANGED <<status, attempts, leaseLeft, retryLeft, started, calls, lostResult, stoppedBeforeStart, resultAttempt, staged>>

AllowedTransitions == [][AllowedTransition /\ AllowedStep]_vars
=============================================================================
