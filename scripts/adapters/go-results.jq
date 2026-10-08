def reject($reason): error($reason);
($expected[0] | map({key:(.package+"::"+.test_name),value:.}) | from_entries) as $inventory |
if ($events | length) == 0 then reject("no Go JSON events") else . end |
(reduce $events[] as $event ({tests:{},packages:{}};
  if ($event | type) != "object" or ($event.Action | type) != "string" then reject("malformed Go event")
  elif $event.Action == "build-fail" then reject("Go compilation failed")
  elif ($event.Action == "build-output" or $event.Action == "build-start" or $event.Action == "build-pass") then .
  elif ($event.Package | type) != "string" then reject("Go event has no package")
  elif ($event.Test // "") != "" then
    ($event.Package+"::"+$event.Test) as $id |
    if $inventory[$id] == null then reject("unexpected Go test identity: "+$id)
    elif $event.Action == "run" then
      if .tests[$id] != null then reject("duplicate Go test execution: "+$id)
      else .tests[$id] = {started:true} end
    elif ($event.Action == "pass" or $event.Action == "fail" or $event.Action == "skip") then
      if .tests[$id].started != true or .tests[$id].outcome != null then reject("invalid terminal Go test event: "+$id)
      else .tests[$id].outcome = $event.Action end
    elif ($event.Action == "output" or $event.Action == "pause" or $event.Action == "cont") then .
    else reject("unsupported Go test event: "+$event.Action) end
  elif $event.Action == "start" then
    if .packages[$event.Package] != null then reject("duplicate Go package execution")
    else .packages[$event.Package] = {started:true} end
  elif ($event.Action == "pass" or $event.Action == "fail" or $event.Action == "skip") then
    if .packages[$event.Package].outcome != null then reject("duplicate Go package outcome")
    else .packages[$event.Package].outcome = $event.Action end
  elif $event.Action == "output" then .
  else reject("unsupported Go package event: "+$event.Action) end
)) as $state |
[$inventory | to_entries[] | select($state.tests[.key].outcome == null) | .key] as $missing |
if ($missing | length) > 0 then reject("expected Go cases did not finish: "+($missing | join(", "))) else . end |
[$inventory | to_entries[] | select(.value.is_group != true and $state.tests[.key].outcome == "fail") | .value.package] as $failed_packages |
[$inventory | to_entries[] | select(.value.is_group == true and $state.tests[.key].outcome == "fail") | . as $parent |
  select(([$inventory | to_entries[] | select(.value.is_group != true and (.key | startswith($parent.key+"/")) and $state.tests[.key].outcome == "fail")] | length) == 0) | .key] as $unexplained_parents |
if ($unexplained_parents | length) > 0 then reject("parent failure has no failing case: "+($unexplained_parents|join(", "))) else . end |
[$state.packages | to_entries[] | . as $package |
  select(.value.outcome == null or (.value.outcome == "fail" and ($failed_packages | index($package.key)) == null)
    or (.value.outcome != "fail" and ($failed_packages | index($package.key)) != null))] as $bad_packages |
if ($bad_packages | length) > 0 then reject("incomplete or unexplained Go package failure") else . end |
if ($process_exit != 0 and ($process_exit != 1 or ($failed_packages|length) == 0)) then reject("unexplained Go process failure") else . end |
if $process_exit == 0 and ($failed_packages|length) > 0 then reject("Go process success contradicts failed cases") else . end |
if ([$inventory | to_entries[] | select($state.packages[.value.package].outcome == null)] | length) > 0 then reject("expected Go package did not finish") else . end |
{
  examples:[$expected[0][] | select(.is_group != true) | . + {status:(if $state.tests[.id].outcome == "pass" then "passed" elif $state.tests[.id].outcome == "fail" then "failed" else "pending" end)}],
  groups:[$expected[0][] | select(.is_group == true)]
}
