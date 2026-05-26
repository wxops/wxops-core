REGISTRY ?= ghcr.io/wxops
VERSION  ?= latest

PACKAGES := gitea-user gitea-org gitea-team gitea-repository

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
	@bash scripts/validate-packages.sh

.PHONY: clean
clean: ## Remove local .xpkg build artifacts
	rm -f *.xpkg

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
changelog: ## Regenerate CHANGELOG.md from git history (requires git-cliff)
	git-cliff -o CHANGELOG.md

.PHONY: changelog-preview
changelog-preview: ## Print upcoming changelog to stdout without writing
	git-cliff

# ── Help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
