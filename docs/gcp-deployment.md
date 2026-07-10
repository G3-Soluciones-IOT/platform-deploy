# GCP deployment

This deployment runs Docker Compose on the private Compute Engine VM. Images are
published by GitHub Actions to Artifact Registry using Workload Identity
Federation; no service-account key file is used.

## Required VM identity

Attach `jameofit-vm-runtime@jameofit.iam.gserviceaccount.com` to the VM. It
must be allowed to read the runtime secrets and pull from
`southamerica-west1-docker.pkg.dev/jameofit/jameofit-docker`.

## Deploy an immutable release

Run from the root of `platform-deploy` after every service CD workflow has
published its own immutable `sha-<commit>` image tag:

```bash
export CONFIG_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_CONFIG_COMMIT
export EUREKA_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_EUREKA_COMMIT
export IAM_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_IAM_COMMIT
export GATEWAY_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_GATEWAY_COMMIT
export GOALS_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_GOALS_COMMIT
export MEAL_PLANS_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_MEAL_PLANS_COMMIT
export NUTRITIONIST_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_NUTRITIONIST_COMMIT
export PROFILES_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_PROFILES_COMMIT
export RECIPES_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_RECIPES_COMMIT
export TRACKING_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_TRACKING_COMMIT
export IOT_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_IOT_COMMIT
export NUTRITION_AI_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_NUTRITION_AI_COMMIT
./scripts/gcp-load-secrets.sh
./scripts/gcp-up.sh
./scripts/gcp-healthcheck.sh
```

`gcp-load-secrets.sh` reads a URL, username and password secret for each
PostgreSQL service: IAM, Goals, Meal Plans, Profiles, Recipes, Tracking, IoT,
Nutritionist and Nutrition AI. It writes `env/gcp.env` with mode `0600`; that
generated file is ignored by Git.

The default deployment starts config-service, eureka-service, iam-service,
gateway-service, goals-service, meal-plans-service, profiles-service,
recipes-service, tracking-service, iot-service, nutritionist-service and
nutrition-ai-service. `communication-service` is excluded.

`communication-service` is not part of the first deployment. After an
existing MongoDB secret has been provisioned, enable it explicitly:

```bash
export COMMUNICATION_MONGODB_SECRET_ID=EXISTING_SECRET_MANAGER_SECRET_ID
export COMMUNICATION_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_COMMUNICATION_COMMIT
export COMPOSE_PROFILES=communication
./scripts/gcp-load-secrets.sh
./scripts/gcp-up.sh
```

Each PostgreSQL service receives its own Cloud SQL datasource variables. Legacy
`jameofit-db-url`, `jameofit-db-username`, and `jameofit-db-password` secrets
are not used by this deployment.

## Flyway database migrations

JPA services run Flyway on startup and Hibernate validates the final schema with
`ddl-auto=validate`. The first rollout uses:

```bash
SPRING_FLYWAY_BASELINE_ON_MIGRATE=true
```

Keep that value only while adopting Flyway on Cloud SQL databases that already
contain Hibernate-created tables. Flyway will mark the existing schema as
version `1` and then run later migrations, including master-data seeds. After
each service database has `flyway_schema_history`, set:

```bash
SPRING_FLYWAY_BASELINE_ON_MIGRATE=false
```

Use service logs to confirm that migrations ran before considering the rollout
complete. Do not delete or edit rows in `flyway_schema_history` manually.

Config Server and Eureka bind only to loopback on the VM. Gateway uses
`GATEWAY_BIND_ADDRESS`; restrict access through the private network, an
approved internal load balancer, or a proxy.

## Healthcheck scope

`gcp-healthcheck.sh` validates Config Server, Eureka and Gateway through their
Actuator health endpoints, then validates IAM JWKS through the confirmed
Gateway route `/api/v1/jwks/.well-known/jwks.json`.

TODO: no domain-service health route has been confirmed for this deployment, so
the script intentionally does not invent or call domain endpoints.
`communication-service` is not checked unless its profile is introduced with a
confirmed endpoint in a later change.

## Deploy one changed service

Use `gcp-up.sh` for a first boot, recovery, or a full platform rollout. For the
normal loop after changing a single service, update only that service:

```bash
./scripts/gcp-deploy-service.sh payments-service sha-REPLACE_WITH_PAYMENTS_COMMIT
```

The script updates the service image tag in `env/gcp.env`, pulls the image,
recreates only that container with `--no-deps`, and waits for the expected
Eureka registration. If the service fails to register, it prints container
status and recent logs.

If `env/gcp.env` already has the desired tag, omit the second argument:

```bash
./scripts/gcp-deploy-service.sh payments-service
```

For development or staging, you can refresh immutable tags from Artifact
Registry instead of looking them up manually:

```bash
./scripts/gcp-refresh-image-tags.sh payments-service
./scripts/gcp-deploy-service.sh payments-service
```

Without service arguments, `gcp-refresh-image-tags.sh` updates every active
service in `env/gcp.env` to the newest Artifact Registry tag matching
`sha-<7-hex-character>`. Use explicit tags for production releases when you
need a fully reviewed version lock.

The GCP service inventory lives in `config/gcp-services.env`. Add new services
there once, then the GCP scripts derive image-tag variables, Eureka apps,
OpenAPI checks and datasource variables from that registry.

## Workflow responsibilities

Use the service workflows with separate responsibilities:

- `ci.yml`: PR and branch validation. It should compile and run tests, but not
  publish deployable images.
- `docker-build.yml`: optional PR/branch validation for Dockerfile and image
  packaging. Keep it only if Dockerfile validation is useful for that service.
- `cd.yml`: main-branch release. It builds and pushes the immutable
  `sha-<commit>` image used by `platform-deploy`.

The reusable Artifact Registry workflow now exposes `image_tag`, `image_sha`
and `image_latest` outputs. A later service `cd.yml` can use those outputs to
open a PR or commit against `platform-deploy` and update the corresponding
`*_IMAGE_TAG` without recalculating the tag.

To stop the stack without deleting named volumes:

```bash
./scripts/gcp-down.sh
```
