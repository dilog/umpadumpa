# Optional table subset is in the first ship

Grill parked “choose some tables” as a later slice so V1 could stay “whole Database.” The signed-off mockup already has All tables vs Selected tables on Recipe and one-off Pull. We ship that now. Empty `tables` still means the entire Database. This is a field on Recipe/Pull, not a new object.

How replace behaves with a subset is ADR 0013.

Rejected: keeping table pick as a later V2, and inventing a separate “partial Pull” type.
