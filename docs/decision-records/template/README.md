# Template ADRs

Template ADRs apply to all Terraform framework repositories derived from this template.

ADR-template/0001, ADR-template/0002, and ADR-template/0004 were authored
during the initial `terraform-framework-template` release-hardening pass.
Their Date fields record the actual decision dates: 0001 on 2026-05-06,
0002 on 2026-05-07, and 0004 on 2026-05-10. They record decisions that
already existed in the template design or were made during that
release-readiness pass, rather than a sequence of independent historical
decisions all made on one day.

ADR-template/0005 records the later manifest-classification rule that lets
derivative frameworks repoint org-control-plane workflow callers to their own
namespace while keeping namespace-agnostic framework files drift-gated.

ADR-template/0003 was withdrawn before release and is intentionally absent.

- [0001: Pin Terraform and Provider Versions Exactly](0001-pin-terraform-and-provider-versions-exactly.md)
- [0002: Keep Reference Framework Credential-Free](0002-keep-reference-framework-credential-free.md)
- [0004: Isolate Pull Request Target Triggers](0004-isolate-pull-request-target-triggers.md)
- [0005: Classify Org Control Plane Callers as Scaffold](0005-classify-org-control-plane-callers-as-scaffold.md)
