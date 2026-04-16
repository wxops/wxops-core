# The "Brain"

>[!NOTE]
>Go controllers, Crossplane Functions, and custom CLI/API logic.

The project is where build the "Glue" that talks to K8s

```text
wxops-core/
├── cmd/
│   └── idp-controller/        # Main entry point for your Go API/Controller
├── internal/
│   ├── controller/            # Business logic for provisioning (Okteto, Crossplane)
│   ├── identity/              # Dex/OIDC integration logic
│   ├── security/              # Vault & Kyverno helper functions
│   └── observability/         # LGTM/OTEL configuration logic
├── api/                       # Your internal IDP API definitions (GRPC/REST)
├── pkg/                       # Reusable Go utilities
├── deployments/               # Dockerfile for the controller itself
└── Makefile                   # Build and test commands
```