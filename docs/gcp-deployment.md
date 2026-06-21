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
export PROFILES_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_PROFILES_COMMIT
export RECIPES_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_RECIPES_COMMIT
export TRACKING_SERVICE_IMAGE_TAG=sha-REPLACE_WITH_TRACKING_COMMIT
./scripts/gcp-load-secrets.sh
./scripts/gcp-up.sh
./scripts/gcp-healthcheck.sh
```

`gcp-load-secrets.sh` reads a URL, username and password secret for each
PostgreSQL service: IAM, Goals, Meal Plans, Profiles, Recipes and Tracking. It
writes `env/gcp.env` with mode `0600`; that generated file is ignored by Git.

The default deployment starts config-service, eureka-service, iam-service,
gateway-service, goals-service, meal-plans-service, profiles-service,
recipes-service and tracking-service. `communication-service` is excluded.

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

To stop the stack without deleting named volumes:

```bash
./scripts/gcp-down.sh
```
