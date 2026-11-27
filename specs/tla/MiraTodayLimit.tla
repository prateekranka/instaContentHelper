--------------------------- MODULE MiraTodayLimit ---------------------------
EXTENDS Naturals, FiniteSets

CONSTANTS Cards, Limit, AppQueuesWhenFull

VARIABLES app, server

vars == <<app, server>>

ActiveOnServer == Cardinality({c \in Cards : server[c] = "running"})

Init ==
    /\ app = [c \in Cards |-> "none"]
    /\ server = [c \in Cards |-> "none"]

Request(c) ==
    /\ app[c] = "none"
    /\ IF ActiveOnServer < Limit
       THEN app' = [app EXCEPT ![c] = "working"] /\ server' = [server EXCEPT ![c] = "running"]
       ELSE /\ app' = [app EXCEPT ![c] = IF AppQueuesWhenFull THEN "waiting" ELSE "working"]
            /\ server' = server

SendWaiting(c) ==
    /\ app[c] = "waiting"
    /\ ActiveOnServer < Limit
    /\ app' = [app EXCEPT ![c] = "working"]
    /\ server' = [server EXCEPT ![c] = "running"]

Reconnect(c) ==
    /\ app[c] = "working" /\ server[c] = "none"
    /\ ActiveOnServer < Limit
    /\ server' = [server EXCEPT ![c] = "running"]
    /\ app' = app

ServerDone(c) ==
    /\ server[c] = "running"
    /\ server' = [server EXCEPT ![c] = "done"]
    /\ app' = [app EXCEPT ![c] = "done"]

Next == \E c \in Cards : Request(c) \/ SendWaiting(c) \/ Reconnect(c) \/ ServerDone(c)

Spec == Init /\ [][Next]_vars
FairSpec == Spec /\ \A c \in Cards : WF_vars(Request(c)) /\ WF_vars(SendWaiting(c)) /\ WF_vars(ServerDone(c))

WorkingIsReal == \A c \in Cards : app[c] = "working" => server[c] = "running" \/ server[c] = "done"
NeverOverLimit == ActiveOnServer <= Limit
AllFinishWithoutReconnect == <>(\A c \in Cards : app[c] = "done")
=============================================================================
