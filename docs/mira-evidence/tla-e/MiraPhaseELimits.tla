-------------------------- MODULE MiraPhaseELimits --------------------------
EXTENDS Naturals, FiniteSets, TLC

CONSTANTS NoteJobs, TextJobs, LegacyJobs, LastDay, TextCap, ActiveLimit

Jobs == NoteJobs \cup TextJobs \cup LegacyJobs
Days == 1..LastDay
Kinds == {"text", "dailyNote"}
Kind(j) == IF j \in NoteJobs THEN "dailyNote" ELSE "text"
Limit(k) == IF k = "dailyNote" THEN 1 ELSE TextCap
NoJob == "none"

VARIABLES day, status, admitted, cache, attempts, reserved, served

vars == <<day, status, admitted, cache, attempts, reserved, served>>
Active == {j \in Jobs : status[j] \in {"queued", "running"}}

Init ==
    /\ day = 1
    /\ status = [j \in Jobs |-> "absent"]
    /\ admitted = [j \in Jobs |-> 0]
    /\ cache = [d \in Days |-> NoJob]
    /\ attempts = [j \in Jobs |-> 0]
    /\ reserved = [d \in Days |-> [k \in Kinds |-> 0]]
    /\ served = NoJob

Enqueue(j) ==
    /\ status[j] = "absent"
    /\ Cardinality(Active) < ActiveLimit
    /\ (j \in LegacyJobs \/ reserved[day][Kind(j)] < Limit(Kind(j)))
    /\ (j \notin NoteJobs \/ cache[day] = NoJob)
    /\ status' = [status EXCEPT ![j] = "queued"]
    /\ admitted' = [admitted EXCEPT ![j] = day]
    /\ cache' = IF j \in NoteJobs THEN [cache EXCEPT ![day] = j] ELSE cache
    /\ served' = IF j \in NoteJobs THEN j ELSE NoJob
    /\ UNCHANGED <<day, attempts, reserved>>

ReuseNote(j) ==
    /\ j \in NoteJobs
    /\ status[j] = "absent"
    /\ cache[day] # NoJob
    /\ served' = cache[day]
    /\ UNCHANGED <<day, status, admitted, cache, attempts, reserved>>

Claim(j) ==
    /\ status[j] = "queued"
    /\ (j \notin NoteJobs \/ (admitted[j] = day /\ attempts[j] = 0))
    /\ IF j \in LegacyJobs
       THEN /\ status' = [status EXCEPT ![j] = "running"]
            /\ UNCHANGED reserved
       ELSE LET k == Kind(j) IN
            IF reserved[day][k] < Limit(k)
            THEN /\ reserved' = [reserved EXCEPT ![day][k] = @ + 1]
                 /\ status' = [status EXCEPT ![j] = "running"]
            ELSE /\ status' = [status EXCEPT ![j] = "failed"]
                 /\ UNCHANGED reserved
    /\ attempts' = [attempts EXCEPT ![j] = @ + 1]
    /\ UNCHANGED <<day, admitted, cache, served>>

Finish(j, result) ==
    /\ status[j] = "running"
    /\ status' = [status EXCEPT ![j] = result]
    /\ UNCHANGED <<day, admitted, cache, attempts, reserved, served>>

Retry(j) ==
    /\ j \notin NoteJobs
    /\ attempts[j] < 3
    /\ Finish(j, "queued")

Expire(j) ==
    /\ j \in NoteJobs
    /\ status[j] = "queued"
    /\ admitted[j] < day
    /\ status' = [status EXCEPT ![j] = "failed"]
    /\ UNCHANGED <<day, admitted, cache, attempts, reserved, served>>

Cancel(j) ==
    /\ j \in Active
    /\ status' = [status EXCEPT ![j] = "cancelled"]
    /\ UNCHANGED <<day, admitted, cache, attempts, reserved, served>>

NewDay ==
    /\ day < LastDay
    /\ day' = day + 1
    /\ served' = NoJob
    /\ UNCHANGED <<status, admitted, cache, attempts, reserved>>

Next ==
    \/ NewDay
    \/ \E j \in NoteJobs : ReuseNote(j)
    \/ \E j \in Jobs : Enqueue(j) \/ Claim(j) \/ Cancel(j) \/ Expire(j) \/ Retry(j)
                    \/ Finish(j, "succeeded") \/ Finish(j, "failed")

Spec == Init /\ [][Next]_vars
ActiveBound == Cardinality(Active) <= ActiveLimit
DailyCaps == \A d \in Days, k \in Kinds : reserved[d][k] <= Limit(k)
NoteAttempts == \A j \in NoteJobs : attempts[j] <= 1
OneNotePerDay == \A d \in Days :
    {j \in NoteJobs : admitted[j] = d} = (IF cache[d] = NoJob THEN {} ELSE {cache[d]})
CorrectCacheResponse == served = NoJob \/ served = cache[day]
StableCache ==
    [][\A d \in Days : cache[d] # NoJob => cache'[d] = cache[d]]_vars
=============================================================================
