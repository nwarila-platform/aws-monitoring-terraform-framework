PYTHON ?= python3
TFLINT ?= tflint

# The deny-all guard scans the whole repository. Only rooted, known runtime/scratch artifacts are
# excluded: Terraform's local cache/state, Python bytecode caches, the `.tmp/` scratch directory
# this org's repositories share, and `.themis/` tool state. These are working-tree-only by
# construction, so excluding them cannot hide a deliverable.
GUARD_EXCLUDE := ^(\.tmp/|\.themis/|terraform/\.terraform/|terraform/terraform\.tfstate(\.backup)?$$|terraform/\.terraform\.tfstate\.lock\.info$$|([^/]+/)*__pycache__/|([^/]+/)*[^/]+\.py[co]$$)

.PHONY: fmt fmt-check init validate test trail-check portability-check docs docs-diff docs-check \
	allowlist-check tflint ci

# Mutating: rewrites HCL in place. Use locally before committing.
# -recursive skips terraform.tfvars.example because fmt only walks .tf and .tfvars extensions,
# so the example is piped through stdin mode separately. Both targets must cover it or a
# contributor could run fmt and still fail fmt-check.
fmt:
	terraform -chdir=terraform fmt -recursive
	@formatted=$$(terraform fmt - < terraform/terraform.tfvars.example) && \
	printf '%s\n' "$$formatted" > terraform/terraform.tfvars.example

# Non-mutating: fails if any file would change. Use in CI.
fmt-check:
	terraform -chdir=terraform fmt -check -recursive
	@terraform fmt -check - < terraform/terraform.tfvars.example > /dev/null || \
	{ echo "terraform/terraform.tfvars.example is not fmt-clean; run 'make fmt'"; exit 1; }
	@# Against the empty tree, so every file is checked rather than only uncommitted changes.
	@# Markdown keeps trailing spaces as hard breaks; the markdownlint config is a byte-identical
	@# template mirror whose trailing blank line is not this repository's to change.
	@git diff --check "$$(git hash-object -t tree /dev/null)" -- . ':!*.md' ':!.markdownlint-cli2.jsonc' || \
	{ echo "whitespace errors; see above"; exit 1; }

init:
	terraform -chdir=terraform init -backend=false -input=false

validate:
	terraform -chdir=terraform validate

test:
	terraform -chdir=terraform test

# The trail gate decides whether the alerts can fire at all, and its silent-pass cases are the
# ones that matter, so its selector logic is proven offline against fixture trail shapes.
trail-check:
	bash tools/test_check_cloudtrail.sh

# providers.tf is the only file that may say where a deployment goes, which is what lets one
# commit deploy to a commercial or a GovCloud account by swapping that file alone. A partition
# written into an ARN, or a region name, anywhere else ties every deployment to one environment.
# The partition fact table in locals.tf is the single, named exception.
portability-check:
	@# Any ARN partition (aws, aws-us-gov, aws-cn, ...), a bare partition string, or a region name
	@# anywhere in a line, quoted or embedded, in any Terraform source under terraform/. Whole-line
	@# comments are skipped; a region named in an inline comment is flagged too, which errs on the
	@# loud side, as does a non-region string shaped like one. providers.tf is exempt: it is the one
	@# file each environment replaces, so a region or an ARN in its partition belongs there. The fact
	@# table is exempt only for its own exact line.
	@files=$$(find terraform -name '*.tf' -not -path '*/.terraform/*'); \
	[ -n "$$files" ] || { echo "portability-check: no Terraform sources found"; exit 1; }; \
	found=$$(grep -nHE 'arn:aws[a-z-]*:|"aws(-[a-z]+)*"|(^|[^[:alnum:]])[a-z]{2}(-gov|-iso[a-z]*)?-(north|south|east|west|central|northeast|northwest|southeast|southwest)-[0-9]+([^[:alnum:]]|$$)' $$files); \
	status=$$?; [ "$$status" -le 1 ] || { echo "portability-check: grep failed ($$status)"; exit 1; }; \
	found=$$(printf '%s\n' "$$found" | grep -v '^terraform/providers.tf:' \
	  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
	  | grep -vE '^terraform/locals.tf:[0-9]+:  global_service_regions = \{ aws = "us-east-1", aws-us-gov = "us-gov-west-1" \}$$' \
	  | grep -v '^$$'); \
	if [ -n "$$found" ]; then \
	  printf 'ERROR: a region or partition is named outside providers.tf:\n%s\n' "$$found"; exit 1; \
	fi; \
	printf 'portability-check: OK — only providers.tf chooses a region, and no partition is written\n'

# Mutating: regenerates the injected block in docs/reference/terraform.md.
docs:
	terraform-docs --config .terraform-docs.yml terraform

# Non-mutating: fails if docs/reference/terraform.md is out of sync with terraform/.
docs-diff:
	terraform-docs --config .terraform-docs.yml --output-check terraform

docs-check:
	$(PYTHON) tools/check_docs_layout.py

# Bidirectional deny-all allowlist guard. The forward half catches deliverable files that exist on
# disk but git would silently omit; the reverse half catches stale unignore entries after a
# path is renamed or deleted.
allowlist-check:
	@ignored=$$(git ls-files --others --ignored --exclude-standard -- . 2>/dev/null \
	  | grep -vE '$(GUARD_EXCLUDE)' || true); \
	if [ -n "$$ignored" ]; then \
	  printf 'ERROR: repository files are NOT allowlisted in .gitignore:\n'; \
	  printf '%s\n' "$$ignored" | sed 's/^/  /'; \
	  printf 'Add an explicit "!/<path>" line to .gitignore, or remove the non-deliverable artifact.\n'; \
	  exit 1; \
	else \
	  printf 'allowlist-check: OK — every repository file is explicitly allowlisted\n'; \
	fi
	@# Root-level core-file rules intentionally use !name syntax; this reverse check polices rooted
	@# !/ entries only.
	@orphans=$$(grep '^!/' .gitignore | sed 's|^!/||; s|/\*\*$$||' | while read -r p; do \
	  case "$$p" in \
	    */) git ls-files --cached --others --exclude-standard -- "$${p%/}" | grep -q . \
	          || echo "$$p" ;; \
	    *)  git ls-files --error-unmatch "$$p" >/dev/null 2>&1 || echo "$$p" ;; \
	  esac; \
	done); \
	if [ -n "$$orphans" ]; then \
	  printf 'ERROR: .gitignore allowlists paths not in the tracked set:\n'; \
	  printf '%s\n' "$$orphans" | sed 's|^|  !/|'; \
	  exit 1; \
	else \
	  printf 'allowlist-check: OK — every rooted allowlist entry resolves\n'; \
	fi

tflint:
	$(TFLINT) --config "$(CURDIR)/.tflint.hcl" --chdir terraform

ci:
	$(MAKE) fmt-check
	$(MAKE) init
	$(MAKE) validate
	$(MAKE) test
	$(MAKE) trail-check
	$(MAKE) portability-check
	$(MAKE) tflint
	$(MAKE) docs-diff
	$(MAKE) docs-check
	$(MAKE) allowlist-check
