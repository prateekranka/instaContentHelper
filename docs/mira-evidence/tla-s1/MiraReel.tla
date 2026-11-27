------------------------------- MODULE MiraReel -------------------------------
EXTENDS Naturals, Sequences

CONSTANTS MaxRev, MaxBrief, MaxUndo, MaxTouch,
          ProjectsPathGuarded, ShootingScreenGuarded, StageHasApproval,
          RefusedShownAsWaiting, StopUnknownStops

Screens == {"words", "project", "shots", "shooting", "done"}
NoJob == [op |-> "none", st |-> "none", rev |-> 0, known |-> FALSE, forScript |-> 0, briefAt |-> 0]

VARIABLES script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
          job, inputRev, screen, opened, stuck, undo, stopStuck, inStack

vars == <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
          job, inputRev, screen, opened, stuck, undo, stopStuck, inStack>>

Stale == boardSrc # script \/ boardBrief # briefRev
NeedsShots == boardSrc # 0 /\ Stale
IsApproved == approved = script /\ script # 0
CanFilm == boardSrc # 0 /\ ~Stale /\ IsApproved
Stage ==
    IF boardSrc = 0 \/ Stale THEN "planning"
    ELSE IF StageHasApproval /\ ~IsApproved THEN "approving"
    ELSE IF filmed = "all" THEN "complete"
    ELSE IF started THEN "filming" ELSE "ready"

Working == job.st = "working"
Waiting == job.st = "waiting"
Proposal == job.op = "reviseScript" /\ job.st = "succeeded"
Busy == Working \/ Waiting \/ Proposal
Applying == job.op = "reviseStoryboard" /\ job.st = "succeeded" /\ ~stuck

Checkpoint == [script |-> script, boardSrc |-> boardSrc, boardBrief |-> boardBrief,
               approved |-> approved, started |-> started, filmed |-> filmed, briefRev |-> briefRev]
Push == undo' = IF Len(undo) < MaxUndo THEN Append(undo, Checkpoint) ELSE Append(Tail(undo), Checkpoint)
Touch == inputRev' = inputRev + 1

Init ==
    /\ script = 1 /\ nextRev = 2 /\ approved = 0
    /\ boardSrc = 1 /\ boardBrief = 0 /\ briefRev = 0
    /\ started = FALSE /\ filmed = "none"
    /\ job = NoJob /\ inputRev = 0
    /\ screen = "words" /\ opened = FALSE /\ stuck = FALSE
    /\ undo = <<>> /\ stopStuck = FALSE /\ inStack = FALSE

NewJob(op, rev) ==
    \E accepted \in BOOLEAN :
        job' = [op |-> op,
                st |-> IF accepted \/ ~RefusedShownAsWaiting THEN "working" ELSE "waiting",
                rev |-> rev, known |-> accepted, forScript |-> script, briefAt |-> briefRev]

AskRevise ==
    /\ screen = "words" /\ ~Busy
    /\ NewJob("reviseScript", inputRev)
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   inputRev, screen, opened, stuck, undo, stopStuck>>

ServerFinish ==
    /\ Working /\ job.known
    /\ \E s \in {"succeeded", "failed"} : job' = [job EXCEPT !.st = s]
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   inputRev, screen, opened, stuck, undo, stopStuck>>

Reconnect ==
    /\ Working /\ ~job.known
    /\ job' = [job EXCEPT !.known = TRUE]
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   inputRev, screen, opened, stuck, undo, stopStuck>>

SendAgain ==
    /\ Waiting
    /\ job' = [job EXCEPT !.st = "working", !.known = TRUE]
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   inputRev, screen, opened, stuck, undo, stopStuck>>

Stop ==
    /\ screen = "words" /\ (Working \/ Waiting)
    /\ IF job.known
       THEN /\ \E s \in {"cancelled", "succeeded"} : job' = [job EXCEPT !.st = s]
            /\ stopStuck' = stopStuck
       ELSE IF StopUnknownStops
       THEN /\ job' = [job EXCEPT !.st = "cancelled"]
            /\ stopStuck' = stopStuck
       ELSE /\ job' = job
            /\ stopStuck' = TRUE
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   inputRev, screen, opened, stuck, undo>>

UseThis ==
    /\ screen = "words" /\ Proposal
    /\ inputRev = job.rev
    /\ nextRev <= MaxRev
    /\ Push /\ Touch
    /\ script' = nextRev /\ nextRev' = nextRev + 1
    /\ approved' = 0 /\ job' = NoJob
    /\ UNCHANGED <<boardSrc, boardBrief, briefRev, started, filmed, screen, opened, stuck, stopStuck>>

KeepMine ==
    /\ screen = "words"
    /\ Proposal \/ (job.st \in {"failed", "cancelled"})
    /\ job' = NoJob
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   inputRev, screen, opened, stuck, undo, stopStuck>>

RequestShotsAfter ==
    \/ NewJob("reviseStoryboard", inputRev + 1)
    \/ job' = job

Approve ==
    /\ screen = "words" /\ ~Busy /\ script # 0 /\ approved # script
    /\ Push /\ Touch
    /\ approved' = script
    /\ IF boardSrc # 0 /\ Stale
       THEN /\ RequestShotsAfter /\ stuck' = FALSE
            /\ UNCHANGED <<screen, opened, started>>
       ELSE /\ job' = job /\ stuck' = stuck
            /\ ~opened /\ opened' = TRUE /\ screen' = "shooting" /\ started' = TRUE
    /\ UNCHANGED <<script, nextRev, boardSrc, boardBrief, briefRev, filmed, stopStuck>>

StartFromWords ==
    /\ screen = "words" /\ IsApproved /\ ~NeedsShots /\ ~Busy /\ ~opened /\ boardSrc # 0
    /\ opened' = TRUE /\ screen' = "shooting" /\ started' = TRUE
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, filmed,
                   job, inputRev, stuck, undo, stopStuck>>

RetryShots ==
    /\ screen = "words" /\ IsApproved /\ NeedsShots /\ ~Applying /\ ~Busy
    /\ NewJob("reviseStoryboard", inputRev)
    /\ stuck' = FALSE
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   inputRev, screen, opened, undo, stopStuck>>

Advance ==
    /\ screen = "words" /\ ~opened /\ IsApproved
    /\ job.op = "reviseStoryboard" /\ job.st = "succeeded"
    /\ IF inputRev = job.rev /\ job.forScript = script /\ job.briefAt = briefRev
       THEN /\ Push /\ Touch
            /\ boardSrc' = script /\ boardBrief' = briefRev
            /\ filmed' = IF filmed = "none" THEN "none" ELSE "some"
            /\ job' = NoJob
            /\ opened' = TRUE /\ screen' = "shooting" /\ started' = TRUE
            /\ stuck' = stuck
       ELSE /\ stuck' = TRUE
            /\ UNCHANGED <<boardSrc, boardBrief, filmed, job, opened, screen, started, undo, inputRev>>
    /\ UNCHANGED <<script, nextRev, approved, briefRev, stopStuck>>

GoTo(s) ==
    /\ screen # s
    /\ screen' = s
    /\ opened' = IF s = "words" THEN FALSE ELSE opened
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   job, inputRev, stuck, undo, stopStuck>>

Navigate == GoTo("words") \/ GoTo("project") \/ GoTo("shots")

ShotListFilm ==
    /\ screen = "shots" /\ boardSrc # 0 /\ ~Stale
    /\ ProjectsPathGuarded => IsApproved
    /\ screen' = "shooting" /\ started' = TRUE
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, filmed,
                   job, inputRev, opened, stuck, undo, stopStuck>>

ShotListApprove ==
    /\ ProjectsPathGuarded
    /\ screen = "shots" /\ boardSrc # 0 /\ ~Stale /\ ~IsApproved
    /\ GoTo("words")

FilmShot ==
    /\ screen = "shooting" /\ boardSrc # 0 /\ ~Stale
    /\ ShootingScreenGuarded => IsApproved
    /\ \E f \in {"some", "all"} : filmed' = f
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started,
                   job, inputRev, screen, opened, stuck, undo, stopStuck>>

Finish ==
    /\ screen = "shooting" /\ Stage = "complete"
    /\ screen' = "done"
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   job, inputRev, opened, stuck, undo, stopStuck>>

EditScript ==
    /\ screen = "project" /\ nextRev <= MaxRev
    /\ Push /\ Touch
    /\ script' = nextRev /\ nextRev' = nextRev + 1 /\ approved' = 0
    /\ UNCHANGED <<boardSrc, boardBrief, briefRev, started, filmed, job, screen, opened, stuck, stopStuck>>

ChangeBrief ==
    /\ screen = "project"
    /\ \E b \in 0..MaxBrief : b # briefRev /\ briefRev' = b
    /\ Touch
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, started, filmed,
                   job, screen, opened, stuck, undo, stopStuck>>

Undo ==
    /\ screen = "project" /\ Len(undo) > 0
    /\ LET c == undo[Len(undo)] IN
        /\ script' = c.script /\ boardSrc' = c.boardSrc /\ boardBrief' = c.boardBrief
        /\ approved' = c.approved /\ started' = c.started /\ filmed' = c.filmed
        /\ briefRev' = c.briefRev
    /\ undo' = SubSeq(undo, 1, Len(undo) - 1)
    /\ Touch
    /\ UNCHANGED <<nextRev, job, screen, opened, stuck, stopStuck>>

Relaunch ==
    /\ opened' = FALSE /\ stuck' = FALSE
    /\ screen' = IF screen \in {"shooting", "done"} /\ ShootingScreenGuarded /\ ~IsApproved THEN "words"
                 ELSE IF screen = "shooting" /\ boardSrc # 0 /\ ~Stale THEN "shooting"
                 ELSE IF screen = "words" THEN "words" ELSE "project"
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, started, filmed,
                   job, inputRev, undo, stopStuck>>

TabBack ==
    /\ inStack /\ screen # "shooting"
    /\ IF ShootingScreenGuarded /\ ~IsApproved
       THEN /\ screen' = "words" /\ opened' = FALSE /\ started' = started
       ELSE /\ screen' = "shooting" /\ opened' = opened /\ started' = IF CanFilm \/ ~ShootingScreenGuarded THEN TRUE ELSE started
    /\ UNCHANGED <<script, nextRev, approved, boardSrc, boardBrief, briefRev, filmed,
                   job, inputRev, stuck, undo, stopStuck>>

Step ==
    \/ AskRevise \/ ServerFinish \/ Reconnect \/ SendAgain \/ Stop \/ UseThis \/ KeepMine
    \/ Approve \/ StartFromWords \/ RetryShots \/ Advance
    \/ Navigate \/ ShotListFilm \/ ShotListApprove \/ FilmShot \/ Finish
    \/ EditScript \/ ChangeBrief \/ Undo \/ Relaunch

Next ==
    \/ Step /\ inStack' = (inStack \/ (screen' = "shooting" /\ screen = "words"))
    \/ TabBack /\ inStack' = inStack

Spec == Init /\ [][Next]_vars

Bounds == inputRev <= MaxTouch

FilmingNeedsApproval == screen \in {"shooting", "done"} => IsApproved
StageRespectsGate == Stage \in {"ready", "filming", "complete"} => IsApproved
WorkingIsReal == Working => job.known
StopAlwaysStops == ~stopStuck

WordsHasNextStep ==
    screen = "words" =>
        \/ Working
        \/ Waiting
        \/ Proposal
        \/ IsApproved /\ NeedsShots /\ ~Applying
        \/ job.st \in {"failed", "cancelled"}
        \/ ~IsApproved
        \/ IsApproved /\ ~NeedsShots /\ ~opened /\ boardSrc # 0
        \/ Applying
=============================================================================
