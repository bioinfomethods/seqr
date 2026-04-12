# MCRI Keycloak OIDC Integration

The objective is to add support for login to MCRI via integration with
Keycloak.

Crucially, Keycloak integration was ALREADY implemented in a separate branch. Therefore
the primary approach here should be to examine that branch and lift over the changes
to the greatest extent possible. It is fully expected however that significant code
drift has occurred. Therefore a straight merge is not possible. Instead
individual changes have been CHERRY PICKED from the branch. Merge conflicts have
been resolved but the changes are not tested.

NEXT STEPS:
- try to start django and enable the OIDC integration and work through
  whatever issues appear

Notes:
  - the OIDC integration supports not only login, but sychcronisation of the user groups
    from MCRI to Seqr. Dedicated code mapping the claims to user groups was
    created to support this. Implementing this sync could be a phase 2 however
