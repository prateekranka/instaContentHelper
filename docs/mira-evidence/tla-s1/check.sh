#!/bin/bash
set -u
jar=${TLA2TOOLS:-tla2tools.jar}
run() {
  local spec=$1 cfg=$2 label=$3
  out=$(java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers auto -deadlock -config "$cfg" "$spec" 2>&1)
  states=$(echo "$out" | grep -oE '[0-9,]+ distinct states' | tail -1)
  if echo "$out" | grep -q "No error has been found"; then echo "PASS  $label  ($states)"
  else echo "FAIL  $label"; echo "$out" | grep -E "is violated|Temporal properties were violated|Error:" | head -3; fi
}
one() {
  local spec=$1 inv=$2 flags=$3 label=$4
  sed -e '/^INVARIANTS/,$d' "$spec.cfg" > "${spec}_one.cfg"
  for kv in $flags; do sed -i "s/${kv%%=*} = .*/${kv%%=*} = ${kv#*=}/" "${spec}_one.cfg"; done
  printf "INVARIANTS\n    %s\n" "$inv" >> "${spec}_one.cfg"
  run "$spec" "${spec}_one.cfg" "$label"
  rm -f "${spec}_one.cfg"
}
mode=${1:-after}
if [ "$mode" = after ]; then
  for inv in FilmingNeedsApproval StageRespectsGate WorkingIsReal StopAlwaysStops WordsHasNextStep; do
    one MiraReel "$inv" "" "MiraReel $inv"
  done
  run MiraTodayLimit MiraTodayLimit.cfg "MiraTodayLimit WorkingIsReal NeverOverLimit AllFinishWithoutReconnect"
else
  off="ProjectsPathGuarded=FALSE ShootingScreenGuarded=FALSE StageHasApproval=FALSE RefusedShownAsWaiting=FALSE StopUnknownStops=FALSE"
  one MiraReel FilmingNeedsApproval "$off" "before: MiraReel FilmingNeedsApproval (B1, B2)"
  one MiraReel FilmingNeedsApproval "ProjectsPathGuarded=FALSE" "before B1 only: MiraReel FilmingNeedsApproval"
  one MiraReel FilmingNeedsApproval "ShootingScreenGuarded=FALSE" "before B2 only: MiraReel FilmingNeedsApproval"
  one MiraReel StageRespectsGate "StageHasApproval=FALSE" "before B3 only: MiraReel StageRespectsGate"
  one MiraReel WorkingIsReal "RefusedShownAsWaiting=FALSE" "before B4 only: MiraReel WorkingIsReal"
  one MiraReel StopAlwaysStops "StopUnknownStops=FALSE" "before B5 only: MiraReel StopAlwaysStops"
  sed 's/AppQueuesWhenFull = TRUE/AppQueuesWhenFull = FALSE/' MiraTodayLimit.cfg > MiraTodayLimit_before.cfg
  run MiraTodayLimit MiraTodayLimit_before.cfg "before B4: MiraTodayLimit"
  rm -f MiraTodayLimit_before.cfg
fi
rm -rf states *_TTrace_*
