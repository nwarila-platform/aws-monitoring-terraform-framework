# Does this trail's event-selector configuration admit the write management events both alerts
# need? Consumed by tools/check_cloudtrail.sh and proven by tools/test_check_cloudtrail.sh
# against tools/fixtures/event-selectors/. Input is a get-event-selectors response; $sources is
# the list of CloudTrail eventSource values the alerts depend on.

# A selector admits a service unless it names eventSource and leaves that service out.
def admits(sel; svc):
  [ sel.FieldSelectors[]? | select(.Field == "eventSource") ] as $f
  | ($f | length) == 0
    or all($f[];
         (if .Equals then (.Equals | index(svc)) != null else true end)
         and (if .NotEquals then (.NotEquals | index(svc)) == null else true end));

# readOnly true records reads only, which is the silent-green case this gate exists for.
def keeps_writes(sel):
  all(sel.FieldSelectors[]?; .Field != "readOnly" or ((.Equals // []) != ["true"]));

# A basic selector cannot narrow management events by service, so it admits every source.
[
  ( .EventSelectors[]?
    | select(.IncludeManagementEvents and .ReadWriteType != "ReadOnly")
    | { FieldSelectors: [] } ),
  ( .AdvancedEventSelectors[]?
    | select(any(.FieldSelectors[]; .Field == "eventCategory" and (.Equals // []) == ["Management"]))
    | select(keeps_writes(.)) )
] as $qualifying

# Both services must be admitted, though not necessarily by the same selector.
| all($sources[]; . as $svc | any($qualifying[]; admits(.; $svc)))
