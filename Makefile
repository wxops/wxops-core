REGISTRY ?= ghcr.io/wxops

PACKAGES := gitea-user gitea-org gitea-team gitea-repository platform-database-clusters tenant-database tenant-app

# ── Package build & publish ──────────────────────────────────────────────────

.PHONY: build
build: ## Build all Crossplane OCI packages locally (.xpkg files)
	@for pkg in $(PACKAGES); do \
		echo "→ building package/$$pkg"; \
		crossplane xpkg build \
			-f package/$$pkg \
			-o platform-wxops-$$pkg.xpkg \
			--ignore kustomization.yaml; \
	done

.PHONY: push
push: build ## Build and push all packages to the registry
	@for pkg in $(PACKAGES); do \
		echo "→ pushing platform-wxops-$$pkg:$(VERSION)"; \
		crossplane xpkg push \
			$(REGISTRY)/platform-wxops-$$pkg:$(VERSION) \
			-f platform-wxops-$$pkg.xpkg; \
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

# ── Lint & render ────────────────────────────────────────────────────────────

.PHONY: lint
lint: ## YAML lint + kubeconform schema validation
	@echo "→ yamllint"
	@yamllint -c .yamllint.yaml .
	@echo "→ kubeconform (package/)"
	@find package/ -name '*.yaml' | xargs kubeconform \
		-schema-location default \
		-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
		-ignore-missing-schemas \
		-summary

.PHONY: render
render: ## Render example XRs against compositions (offline dry-run)
	@for pkg in $(PACKAGES); do \
		echo "→ rendering examples/$$pkg/xr.yaml"; \
		crossplane beta render \
			examples/$$pkg/xr.yaml \
			package/$$pkg/composition.yaml \
			--function-runner=local \
			2>/dev/null || true; \
	done

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

.PHONY: release-notes
release-notes: ## Generate release-notes/<version>.md from template (usage: make release-notes VERSION=v0.2.0)
	@echo "$(VERSION)" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$' || \
		(echo "error: VERSION must match v<major>.<minor>.<patch>, e.g. make release-notes VERSION=v0.2.0" >&2; exit 1)
	@bash .gitea/scripts/check-release-notes.sh $(VERSION)

.PHONY: release
release: ## Prepare a release commit + tag (no push) — VERSION=vX.Y.Z | BUMP=major|minor|patch | default: auto from commits
	@which git-cliff > /dev/null || (echo "git-cliff not installed — see https://git-cliff.org/docs/installation" && exit 1)
	@if [ -n "$(VERSION)" ]; then \
		ver="$(VERSION)"; \
	elif [ -n "$(BUMP)" ]; then \
		current=$$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"); \
		maj=$$(echo "$$current" | cut -d. -f1 | tr -d v); \
		min=$$(echo "$$current" | cut -d. -f2); \
		pat=$$(echo "$$current" | cut -d. -f3); \
		case "$(BUMP)" in \
			major) ver="v$$((maj+1)).0.0" ;; \
			minor) ver="v$${maj}.$$((min+1)).0" ;; \
			patch) ver="v$${maj}.$${min}.$$((pat+1))" ;; \
			*) echo "error: BUMP must be major, minor, or patch" >&2; exit 1 ;; \
		esac; \
	else \
		ver=$$(git-cliff --bumped-version 2>/dev/null); \
		[ -n "$$ver" ] || { echo "error: git-cliff could not resolve next version — pass VERSION=vX.Y.Z or BUMP=major|minor|patch" >&2; exit 1; }; \
	fi; \
	echo "$$ver" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$' \
		|| { echo "error: '$$ver' is not valid semver (expected vX.Y.Z)" >&2; exit 1; }; \
	git diff --quiet && git diff --cached --quiet \
		|| { echo "error: working tree has uncommitted changes — commit or stash before releasing" >&2; exit 1; }; \
	git rev-parse "$$ver" >/dev/null 2>&1 \
		&& { echo "error: tag $$ver already exists" >&2; exit 1; }; \
	echo "→ checking CHANGELOG.md for $$ver"; \
	git-cliff --tag "$$ver" -o CHANGELOG.md; \
	if git diff --quiet -- CHANGELOG.md; then \
		echo "→ CHANGELOG.md already up to date for $$ver"; \
	else \
		echo "→ CHANGELOG.md updated for $$ver"; \
		git add CHANGELOG.md; \
		git commit -m "chore(release): prepare for release $$ver"; \
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
