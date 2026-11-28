--------------------------- MODULE MiraLocation ---------------------------
EXTENDS Sequences

CONSTANT SavedPositionLast
VARIABLES savedTab, homePath, brandPath, position, brandHint, restored

vars == <<savedTab, homePath, brandPath, position, brandHint, restored>>
EditorSections == {"script", "shots"}
Positions == EditorSections \cup {"absent", "otherReel"}

Section(route, hint) ==
    CASE route = "editor" -> IF hint \in {"absent", "shots", "shooting"} THEN "shots" ELSE "script"
      [] OTHER -> route

RECURSIVE Replay(_, _)
Replay(path, hint) ==
    IF path = <<>> THEN hint ELSE Replay(Tail(path), Section(Head(path), hint))

Init ==
    /\ savedTab \in {"home", "brand"}
    /\ homePath \in {<<"editor">>, <<"words", "editor">>, <<"words", "editor", "shooting">>}
    /\ brandPath \in {<<"editor">>, <<"editor", "shooting">>}
    /\ position \in Positions
    /\ brandHint \in EditorSections
    /\ restored = "pending"

Restore ==
    /\ restored = "pending"
    /\ LET stored == IF position \in EditorSections THEN position ELSE "absent"
           homeSeed == IF ~SavedPositionLast /\ savedTab = "home" THEN stored ELSE "absent"
           homeHint == Replay(homePath, homeSeed)
           path == IF savedTab = "home" THEN homePath ELSE brandPath
           hint == IF savedTab = "home" THEN homeHint ELSE brandHint
           activeHint == IF SavedPositionLast /\ stored # "absent" THEN stored ELSE hint
       IN restored' = Section(path[Len(path)], activeHint)
    /\ UNCHANGED <<savedTab, homePath, brandPath, position, brandHint>>

Spec == Init /\ [][Restore]_vars

HomeOnly == savedTab = "home"

LatestEditorSectionWins ==
    LET path == IF savedTab = "home" THEN homePath ELSE brandPath
    IN restored # "pending" /\ path[Len(path)] = "editor" /\ position \in EditorSections
       => restored = position

SavedShootingRouteWins ==
    LET path == IF savedTab = "home" THEN homePath ELSE brandPath
    IN restored # "pending" /\ path[Len(path)] = "shooting" => restored = "shooting"

BrandUsesItsOwnHint ==
    restored # "pending" /\ savedTab = "brand" /\ brandPath = <<"editor">>
        /\ position \notin EditorSections => restored = brandHint
=============================================================================
