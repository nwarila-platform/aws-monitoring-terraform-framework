# Does this trail's event-selector configuration record the write management events the alerts
# need? Consumed by tools/check_cloudtrail.sh and proven by tools/test_check_cloudtrail.sh against
# tools/fixtures/event-selectors/. Input is a get-event-selectors response.
#
# A trail cannot filter EC2 or IAM out of its management events: for management events CloudTrail
# accepts an eventSource selector only as NotEquals kms.amazonaws.com or rdsdata.amazonaws.com. So
# the only way a management-event trail can starve these alerts is by recording reads alone.

def keeps_writes(sel):
  all(sel.FieldSelectors[]?; .Field != "readOnly" or ((.Equals // []) != ["true"]));

[
  ( .EventSelectors[]?
    | select(.IncludeManagementEvents and .ReadWriteType != "ReadOnly") ),
  ( .AdvancedEventSelectors[]?
    | select(any(.FieldSelectors[]; .Field == "eventCategory" and (.Equals // []) == ["Management"]))
    | select(keeps_writes(.)) )
] | length > 0
