REGISTRY ?= ghcr.io/wxops/wxops-core

# datreeio CRDs-catalog ref used for third-party schema lookups. PINNED on
# purpose: tracking `main` would let upstream change what CI accepts with no
# commit in this repo, making the gate non-reproducible. Bump alongside the
# reference stack in CLAUDE.md. Keep in sync with CATALOG_REF in tests/structural.py.
CRDS_CATALOG_REF ?= 52b0261318acc7dd0b66e032759b1f218216b980

PACKAGES := gitea-user gitea-org gitea-team gitea-repository platform-database-clusters tenant-database tenant-app

# ── Package build & publish ──────────────────────────────────────────────────

.PHONY: build
build: ## Build all Crossplane OCI packages locally (.xpkg files)
	@for pkg in $(PACKAGES); do \
		echo "→ building package/$$pkg"; \
		crossplane xpkg build \
			-f package/$$pkg \
			-o $$pkg.xpkg \
			--ignore kustomization.yaml; \
	done

.PHONY: push
push: build ## Build and push all packages to the registry
	@for pkg in $(PACKAGES); do \
		echo "→ pushing $$pkg:$(VERSION)"; \
		crossplane xpkg push \
			$(REGISTRY)/$$pkg:$(VERSION) \
			-f $$pkg.xpkg; \
	done

.PHONY: validate
validate: ## Validate all package directories (crossplane xpkg build, no push)
	@bash .gitea/scripts/validate-packages.sh

.PHONY: clean
clean: ## Remove local .xpkg build artifacts
	rm -f *.xpkg

# ── KCL source management ────────────────────────────────────────────────────

.PHONY: kcl-sync
kcl-sync: ## Embed kcl/{pkg}/main.k into composition.yaml (run after editing KCL source)
	@python3 .gitea/scripts/kcl-sync.py

.PHONY: kcl-check
kcl-check: ## Fail if any composition.yaml is out of sync with its kcl/ source
	@python3 .gitea/scripts/kcl-sync.py --check

.PHONY: readme-sync
readme-sync: ## Regenerate the README.md packages table from VERSIONS.yaml
	@python3 .gitea/scripts/gen-readme-packages.py

.PHONY: readme-check
readme-check: ## Fail if README.md packages table is out of sync with VERSIONS.yaml
	@python3 .gitea/scripts/gen-readme-packages.py --check

# ── Lint & render ────────────────────────────────────────────────────────────

.PHONY: lint
lint: ## YAML lint + kubeconform schema validation
	@echo "→ yamllint"
	@yamllint -c .yamllint.yaml .
	@echo "→ kubeconform (package/)"
	@find package/ -name '*.yaml' | xargs kubeconform \
		-schema-location default \
		-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/$(CRDS_CATALOG_REF)/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
		-ignore-missing-schemas \
		-summary

# Every function any composition references must be listed, or render fails with
# "unknown function ... is it listed in the render input?".
FUNCTIONS := providers/function-kcl.yaml \
             providers/function-patch-and-transform.yaml \
             providers/function-extra-resources.yaml

.PHONY: render
render: ## Render example XRs against compositions (offline dry-run)
	@fns="$$(mktemp)"; err="$$(mktemp)"; \
	for f in $(FUNCTIONS); do echo "---"; cat "$$f"; done > "$$fns"; \
	failed=""; \
	for pkg in $(PACKAGES); do \
		echo "→ rendering examples/$$pkg/xr.yaml"; \
		req=""; \
		if [ -f "examples/$$pkg/required-resources.yaml" ]; then \
			req="--required-resources=examples/$$pkg/required-resources.yaml"; \
		fi; \
		if ! crossplane composition render \
				examples/$$pkg/xr.yaml \
				package/$$pkg/composition.yaml \
				"$$fns" $$req 2>"$$err"; then \
			sed 's/^/    /' "$$err" >&2; \
			failed="$$failed $$pkg"; \
		fi; \
	done; \
	rm -f "$$fns" "$$err"; \
	if [ -n "$$failed" ]; then \
		echo "" >&2; echo "render FAILED:$$failed" >&2; exit 1; \
	fi

# ── Tests ────────────────────────────────────────────────────────────────────
# Offline. No cluster required — `crossplane composition render` runs the real
# function images in Docker. See tests/README.md for what this can and cannot
# catch; notably it cannot catch provider RBAC gaps.

PYTHON ?= python3

.PHONY: test
test: test-xrd test-api-compat test-golden test-invariants ## Run the offline test suite (the merge gate)
	@echo ""
	@echo "test suite passed"

.PHONY: test-xrd
test-xrd: ## Strict: XRs conform to our XRDs; negative cases are rejected
	@$(PYTHON) tests/xrd.py

.PHONY: test-golden
test-golden: ## Golden render tests — output vs committed expectations
	@$(PYTHON) tests/golden.py

.PHONY: test-invariants
test-invariants: ## Rules that must hold for every package and case
	@$(PYTHON) tests/invariants.py

.PHONY: test-api-compat
test-api-compat: ## Released API stays additive — schema diff, XR replay, golden resource checks vs last release
	@$(PYTHON) tests/api_compat.py
	@$(PYTHON) tests/api_compat.py --self-test

.PHONY: test-structural
test-structural: ## Best-effort third-party schema filter (NOT in `make test`)
	@$(PYTHON) tests/structural.py

.PHONY: test-update
test-update: ## Regenerate goldens after an intentional composition change
	@$(PYTHON) tests/golden.py --update

.PHONY: test-deps
test-deps: ## Install the test suite's Python dependencies
	@pip install -r tests/requirements.txt

# ── Cluster install ───────────────────────────────────────────────────────────

.PHONY: providers
providers: ## Install shared providers and functions (run once per cluster)
	kubectl apply -f providers/

.PHONY: install
install: ## Install all packages from registry (production)
	kubectl apply -k package/

.PHONY: uninstall
uninstall: ## Remove all registry-installed Configuration resources
	kubectl delete -k package/ --ignore-not-found

.PHONY: install-dev
install-dev: ## Apply XRDs and Compositions directly — no registry needed (development)
	kubectl apply -k package/dev/

.PHONY: uninstall-dev
uninstall-dev: ## Remove directly applied XRDs and Compositions
	kubectl delete -k package/dev/ --ignore-not-found

# ── Changelog ────────────────────────────────────────────────────────────────

.PHONY: changelog
changelog: ## Regenerate CHANGELOG.md from full git history (requires git-cliff)
	@which git-cliff > /dev/null || (echo "git-cliff not installed — see https://git-cliff.org/docs/installation" && exit 1)
	git-cliff -o CHANGELOG.md

.PHONY: changelog-preview
changelog-preview: ## Preview unreleased changelog without writing
	@which git-cliff > /dev/null || (echo "git-cliff not installed — see https://git-cliff.org/docs/installation" && exit 1)
	git-cliff --unreleased --strip all

# ── Release ───────────────────────────────────────────────────────────────────
# A release is named by the day it is cut — release-YYYY-MM-DD (UTC), .2 for a
# second one that day. Compatibility is not carried by the name: it is the XRD
# API version, held additive-only by tests/api_compat.py. See
# release-notes/README.md.

.PHONY: release-notes
release-notes: ## Scaffold release-notes/<release>.md with its compatibility report (VERSION defaults to today)
	@ver="$(VERSION)"; [ -n "$$ver" ] || ver=$$(python3 .gitea/scripts/release-state.py next); \
	echo "$$ver" | grep -qE '^release-[0-9]{4}-[0-9]{2}-[0-9]{2}(\.[0-9]+)?$$' || \
		{ echo "error: VERSION must look like release-YYYY-MM-DD[.N], e.g. make release-notes VERSION=release-2026-09-11" >&2; exit 1; }; \
	bash .gitea/scripts/check-release-notes.sh "$$ver"

.PHONY: release-check
release-check: ## Fail if VERSIONS.yaml and package/install/ disagree
	@python3 .gitea/scripts/release-state.py check

# The release commit skips the test-api-compat hook: `release-state.py write`
# has just run that same gate on this exact tree, and rerunning it after the
# allowlist is cleared would re-fail every break the allowlist permitted.
.PHONY: release
release: ## Prepare a release commit + tag (no push) — VERSION=release-YYYY-MM-DD[.N] (default: today, UTC) | ALL=1 rebuilds every package
	@which git-cliff > /dev/null || (echo "git-cliff not installed — see https://git-cliff.org/docs/installation" && exit 1)
	@echo ""
	@echo "  ROADMAP.md, README.md, docs/, and release-notes/ get staged and"
	@echo "  committed together with CHANGELOG.md below — go update whatever's"
	@echo "  drifted before this runs, or right now in another terminal, since"
	@echo "  nothing else in the tree may be dirty (see the check below)."
	@echo ""
	@ver="$(VERSION)"; [ -n "$$ver" ] || ver=$$(python3 .gitea/scripts/release-state.py next); \
	all=""; [ -z "$(ALL)" ] || all="--all"; \
	echo "$$ver" | grep -qE '^release-[0-9]{4}-[0-9]{2}-[0-9]{2}(\.[0-9]+)?$$' \
		|| { echo "error: '$$ver' is not a release name (expected release-YYYY-MM-DD[.N])" >&2; exit 1; }; \
	dirty=$$(git status --porcelain -- . ':!ROADMAP.md' ':!README.md' ':!docs' ':!release-notes' ':!CHANGELOG.md'); \
	[ -z "$$dirty" ] \
		|| { echo "error: working tree has uncommitted changes outside ROADMAP.md/README.md/docs/release-notes/CHANGELOG.md — commit or stash before releasing:" >&2; echo "$$dirty" >&2; exit 1; }; \
	git rev-parse -q --verify "refs/tags/$$ver" >/dev/null \
		&& { echo "error: tag $$ver already exists" >&2; exit 1; }; \
	echo "→ classifying changes and pinning packages for $$ver"; \
	python3 .gitea/scripts/release-state.py write "$$ver" $$all || exit 1; \
	python3 .gitea/scripts/gen-readme-packages.py; \
	echo "→ writing CHANGELOG.md for $$ver"; \
	git-cliff --tag "$$ver" -o CHANGELOG.md; \
	git add CHANGELOG.md ROADMAP.md README.md docs/ release-notes/ \
		VERSIONS.yaml package/install/ tests/api-compat-allow.yaml; \
	if git diff --cached --quiet; then \
		echo "→ nothing to commit for $$ver — no package pins, notes or docs changed"; \
	else \
		echo "→ staged for $$ver:"; \
		git diff --cached --name-only | sed 's/^/    /'; \
		SKIP=no-commit-to-branch,test-api-compat git commit -m "chore(release): prepare for release $$ver"; \
	fi; \
	echo "→ tagging $$ver"; \
	git tag "$$ver"; \
	echo ""; \
	echo "✓ Release $$ver prepared locally."; \
	echo "  Review with: git log -2 --stat"; \
	echo ""; \
	echo "  Publish when ready:"; \
	echo "    git push origin main"; \
	echo "    git push origin $$ver"

# ── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
