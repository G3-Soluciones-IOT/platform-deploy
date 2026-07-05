# Auth0 and legacy JWT manual checks

This deployment supports Auth0 as the primary JWT issuer while keeping IAM legacy JWTs behind feature flags during migration.

## Required environment

Set these values before generating `env/gcp.env` with `scripts/gcp-load-secrets.sh`:

```bash
export AUTH0_ISSUER_URI="https://YOUR_AUTH0_DOMAIN/"
export AUTH0_AUDIENCE="YOUR_AUTH0_API_IDENTIFIER"
export LEGACY_JWT_ENABLED=true
export LEGACY_JWKS_ENABLED=true
export LEGACY_JWT_ISSUER=iam-service
export LEGACY_JWT_JWK_SET_URI=http://iam-service:8081/api/v1/jwks/.well-known/jwks.json
```

`AUTH0_ISSUER_URI` must include the trailing slash.

For the current Auth0 development tenant:

```bash
export AUTH0_ISSUER_URI="https://dev-e5ik5gbwpzkcqfrw.us.auth0.com/"
export AUTH0_AUDIENCE="https://api.jameofit.dev"
```

## Config Server checks

```bash
curl -fsS http://127.0.0.1:8888/gateway-service/gcp \
  | jq '.propertySources[].source | with_entries(select(.key | test("auth0|legacy.jwt|issuer-uri")))'
```

Expected keys:

```text
spring.security.oauth2.resource-server.jwt.issuer-uri
auth0.audience
legacy.jwt.enabled
legacy.jwt.issuer
legacy.jwt.jwk-set-uri
```

```bash
curl -fsS http://127.0.0.1:8888/iam-service/gcp \
  | jq '.propertySources[].source | with_entries(select(.key | test("auth0|legacy-jwt|legacy-jwks")))'
```

Expected keys:

```text
authorization.legacy-jwt.enabled
authorization.legacy-jwks.enabled
auth0.issuer-uri
auth0.audience
```

## Auth0 token through Gateway and IAM

Use a valid Auth0 access token whose `iss` matches `AUTH0_ISSUER_URI` and whose `aud` contains `AUTH0_AUDIENCE`.

The current test endpoint is:

```text
GET /api/v1/users
```

It requires one of these authorities:

```text
read:users
ROLE_ADMIN
```

```bash
AUTH0_ACCESS_TOKEN="REPLACE_WITH_ACCESS_TOKEN"

curl --fail-with-body -i \
  -H "Authorization: Bearer ${AUTH0_ACCESS_TOKEN}" \
  https://jameofit.duckdns.org/api/v1/users
```

Expected result:

- Gateway accepts the token if issuer and audience are valid.
- A `401` at Gateway indicates invalid issuer, invalid audience, expired token, or bad signature.
- IAM accepts the token if it contains `permissions: ["read:users", ...]`.
- A `403` at IAM indicates the token is valid but does not have `read:users`.

`goals-service` is the first migrated domain-service pilot. Other downstream domain services can still return `401` while they are configured to validate only legacy IAM JWTs.

## Goals service Auth0 and legacy pilot

`GET /api/v1/goals` is the pilot endpoint with an Auth0 permission check. Auth0 tokens must contain:

```text
permissions: ["read:goals", ...]
```

Legacy IAM JWTs remain accepted while `LEGACY_JWT_ENABLED=true`.

### Auth0 token through Gateway

```bash
AUTH0_ACCESS_TOKEN="REPLACE_WITH_ACCESS_TOKEN_WITH_READ_GOALS"
USER_ID="REPLACE_WITH_USER_ID"

curl --fail-with-body -i \
  -H "Authorization: Bearer ${AUTH0_ACCESS_TOKEN}" \
  "https://jameofit.duckdns.org/api/v1/goals?userId=${USER_ID}"
```

Expected result:

- Gateway accepts the token if issuer and audience are valid.
- `goals-service` accepts the token if `aud` contains `AUTH0_AUDIENCE`.
- `goals-service` allows `GET /api/v1/goals` only if the token includes `read:goals`.

### Auth0 token direct to goals-service

Use this in a local environment where `goals-service` is reachable directly:

```bash
curl --fail-with-body -i \
  -H "Authorization: Bearer ${AUTH0_ACCESS_TOKEN}" \
  "http://localhost:8083/api/v1/goals?userId=${USER_ID}"
```

Expected result:

```text
200 OK
```

or a domain-level response such as `404 Not Found` if no goal exists for that user. A valid token must not produce `401`.

### Wrong audience rejection

```bash
AUTH0_ACCESS_TOKEN_WITH_WRONG_AUDIENCE="REPLACE_WITH_ACCESS_TOKEN_FOR_OTHER_API"

curl -i \
  -H "Authorization: Bearer ${AUTH0_ACCESS_TOKEN_WITH_WRONG_AUDIENCE}" \
  "https://jameofit.duckdns.org/api/v1/goals?userId=${USER_ID}"
```

Expected result:

```text
401 Unauthorized
```

### Missing permission rejection

```bash
AUTH0_ACCESS_TOKEN_WITHOUT_READ_GOALS="REPLACE_WITH_VALID_ACCESS_TOKEN_WITHOUT_READ_GOALS"

curl -i \
  -H "Authorization: Bearer ${AUTH0_ACCESS_TOKEN_WITHOUT_READ_GOALS}" \
  "https://jameofit.duckdns.org/api/v1/goals?userId=${USER_ID}"
```

Expected result:

```text
403 Forbidden
```

### Legacy token compatibility

With `LEGACY_JWT_ENABLED=true` and `LEGACY_JWKS_ENABLED=true`:

```bash
LEGACY_TOKEN="REPLACE_WITH_LEGACY_IAM_TOKEN"

curl --fail-with-body -i \
  -H "Authorization: Bearer ${LEGACY_TOKEN}" \
  "https://jameofit.duckdns.org/api/v1/goals?userId=${USER_ID}"
```

Expected result:

- Gateway accepts the legacy token while `LEGACY_JWT_ENABLED=true`.
- `goals-service` falls back to the IAM JWKS decoder.
- `GET /api/v1/goals` remains compatible with legacy tokens during Phase 2A.

### Missing token

```bash
curl -i "https://jameofit.duckdns.org/api/v1/goals?userId=${USER_ID}"
```

Expected result:

```text
401 Unauthorized
```

## Domain services Auth0 and legacy checks

After the goals-service pilot, these domain services accept Auth0 and legacy JWTs:

| Service | Gateway path | Direct local URL | Read permission | Write permission |
| --- | --- | --- | --- | --- |
| profiles-service | `/api/v1/profiles` | `http://localhost:8086/api/v1/profiles` | `read:profiles` | `write:profiles` |
| tracking-service | `/api/v1/tracking-goals/goal-types` | `http://localhost:8089/api/v1/tracking-goals/goal-types` | `read:tracking` | `write:tracking` |
| meal-plans-service | `/api/v1/meal-plan/templates` | `http://localhost:8084/api/v1/meal-plan/templates` | `read:meal-plans` | `write:meal-plans` |
| recipes-service | `/api/v1/recipes/templates` | `http://localhost:8087/api/v1/recipes/templates` | `read:recipes` | `write:recipes` |
| communication-service | `/api/v1/chat/validate?userId1=1&userId2=2` | `http://localhost:8090/api/v1/chat/validate?userId1=1&userId2=2` | `read:communications` | `write:communications` |

Use Auth0 access tokens whose `aud` contains `AUTH0_AUDIENCE`.

```bash
GATEWAY_URL="http://localhost:8080"
PROFILES_URL="http://localhost:8086"
TRACKING_URL="http://localhost:8089"
MEAL_PLANS_URL="http://localhost:8084"
RECIPES_URL="http://localhost:8087"
COMMUNICATION_URL="http://localhost:8090"
```

### Valid Auth0 token through Gateway

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_PROFILES}" \
  "${GATEWAY_URL}/api/v1/profiles"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_TRACKING}" \
  "${GATEWAY_URL}/api/v1/tracking-goals/goal-types"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_MEAL_PLANS}" \
  "${GATEWAY_URL}/api/v1/meal-plan/templates"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_RECIPES}" \
  "${GATEWAY_URL}/api/v1/recipes/templates"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_COMMUNICATIONS}" \
  "${GATEWAY_URL}/api/v1/chat/validate?userId1=1&userId2=2"
```

Expected result: the gateway and target service accept the token. A domain-level `200`, `204`, `400`, or `404` can be valid depending on local data, but the response must not be `401` or `403`.

### Valid Auth0 token direct to service

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_PROFILES}" \
  "${PROFILES_URL}/api/v1/profiles"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_TRACKING}" \
  "${TRACKING_URL}/api/v1/tracking-goals/goal-types"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_MEAL_PLANS}" \
  "${MEAL_PLANS_URL}/api/v1/meal-plan/templates"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_RECIPES}" \
  "${RECIPES_URL}/api/v1/recipes/templates"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_COMMUNICATIONS}" \
  "${COMMUNICATION_URL}/api/v1/chat/validate?userId1=1&userId2=2"
```

Expected result: the direct service accepts issuer, audience, and required read permission.

### Wrong audience rejection

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WRONG_AUDIENCE}" \
  "${GATEWAY_URL}/api/v1/profiles"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WRONG_AUDIENCE}" \
  "${GATEWAY_URL}/api/v1/tracking-goals/goal-types"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WRONG_AUDIENCE}" \
  "${GATEWAY_URL}/api/v1/meal-plan/templates"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WRONG_AUDIENCE}" \
  "${GATEWAY_URL}/api/v1/recipes/templates"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WRONG_AUDIENCE}" \
  "${GATEWAY_URL}/api/v1/chat/validate?userId1=1&userId2=2"
```

Expected result:

```text
401 Unauthorized
```

### Missing permission rejection

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WITHOUT_PROFILES}" \
  "${GATEWAY_URL}/api/v1/profiles"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WITHOUT_TRACKING}" \
  "${GATEWAY_URL}/api/v1/tracking-goals/goal-types"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WITHOUT_MEAL_PLANS}" \
  "${GATEWAY_URL}/api/v1/meal-plan/templates"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WITHOUT_RECIPES}" \
  "${GATEWAY_URL}/api/v1/recipes/templates"

curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WITHOUT_COMMUNICATIONS}" \
  "${GATEWAY_URL}/api/v1/chat/validate?userId1=1&userId2=2"
```

Expected result:

```text
403 Forbidden
```

### Write permission checks

Use write-capable tokens for non-GET endpoints. The body can still fail domain validation, but the response must not be `401` or `403` when the token has the expected write permission.

```bash
curl -i -X POST -H "Authorization: Bearer ${AUTH0_TOKEN_WRITE_PROFILES}" \
  -H "Content-Type: application/json" \
  --data '{}' \
  "${GATEWAY_URL}/api/v1/profiles"

curl -i -X POST -H "Authorization: Bearer ${AUTH0_TOKEN_WRITE_TRACKING}" \
  -H "Content-Type: application/json" \
  --data '{}' \
  "${GATEWAY_URL}/api/v1/tracking"

curl -i -X POST -H "Authorization: Bearer ${AUTH0_TOKEN_WRITE_MEAL_PLANS}" \
  -H "Content-Type: application/json" \
  --data '{}' \
  "${GATEWAY_URL}/api/v1/meal-plan/users/1"

curl -i -X POST -H "Authorization: Bearer ${AUTH0_TOKEN_WRITE_RECIPES}" \
  -H "Content-Type: application/json" \
  --data '{}' \
  "${GATEWAY_URL}/api/v1/recipes/users/1"
```

Expected result: valid auth, then domain validation response. A write token without the required service permission must return `403`.

`communication-service` currently exposes read-only REST endpoints and STOMP message mappings. Keep `write:communications` available in Auth0 for future REST write endpoints and for a later message-level WebSocket authorization phase.

### Legacy token compatibility

With `LEGACY_JWT_ENABLED=true` and `LEGACY_JWKS_ENABLED=true`:

```bash
curl -i -H "Authorization: Bearer ${LEGACY_TOKEN}" \
  "${GATEWAY_URL}/api/v1/profiles"

curl -i -H "Authorization: Bearer ${LEGACY_TOKEN}" \
  "${GATEWAY_URL}/api/v1/tracking-goals/goal-types"

curl -i -H "Authorization: Bearer ${LEGACY_TOKEN}" \
  "${GATEWAY_URL}/api/v1/meal-plan/templates"

curl -i -H "Authorization: Bearer ${LEGACY_TOKEN}" \
  "${GATEWAY_URL}/api/v1/recipes/templates"

curl -i -H "Authorization: Bearer ${LEGACY_TOKEN}" \
  "${GATEWAY_URL}/api/v1/chat/validate?userId1=1&userId2=2"
```

Expected result: gateway and target services accept the legacy token during migration.

### Missing token

```bash
curl -i "${GATEWAY_URL}/api/v1/profiles"
curl -i "${GATEWAY_URL}/api/v1/tracking-goals/goal-types"
curl -i "${GATEWAY_URL}/api/v1/meal-plan/templates"
curl -i "${GATEWAY_URL}/api/v1/recipes/templates"
curl -i "${GATEWAY_URL}/api/v1/chat/validate?userId1=1&userId2=2"
```

Expected result:

```text
401 Unauthorized
```

## Nutrition AI service Auth0 and legacy checks

`nutrition-ai-service` protects the user-facing endpoint with `read:ai`:

```text
GET /api/v1/ai/home-tip/{userId}
```

Internal routes under `/internal/api/v1/ai/**` remain protected by the existing `X-Internal-Token` mechanism and are not exposed through the Gateway route.

```bash
GATEWAY_URL="http://localhost:8080"
NUTRITION_AI_URL="http://localhost:8091"
USER_ID="1"
```

### Auth0 token through Gateway

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_AI}" \
  "${GATEWAY_URL}/api/v1/ai/home-tip/${USER_ID}"
```

Expected result: valid auth. A domain-level `200` or `204 No Content` is valid depending on whether a tip exists.

### Auth0 token direct to nutrition-ai-service

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_AI}" \
  "${NUTRITION_AI_URL}/api/v1/ai/home-tip/${USER_ID}"
```

Expected result: valid auth. The response must not be `401` or `403`.

### Missing read:ai permission

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WITHOUT_AI}" \
  "${GATEWAY_URL}/api/v1/ai/home-tip/${USER_ID}"
```

Expected result:

```text
403 Forbidden
```

### Wrong audience rejection

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WRONG_AUDIENCE}" \
  "${GATEWAY_URL}/api/v1/ai/home-tip/${USER_ID}"
```

Expected result:

```text
401 Unauthorized
```

### Legacy token compatibility

With `LEGACY_JWT_ENABLED=true` and `LEGACY_JWKS_ENABLED=true`:

```bash
curl -i -H "Authorization: Bearer ${LEGACY_TOKEN}" \
  "${GATEWAY_URL}/api/v1/ai/home-tip/${USER_ID}"
```

Expected result: gateway and `nutrition-ai-service` accept the legacy token during migration.

### Missing token

```bash
curl -i "${GATEWAY_URL}/api/v1/ai/home-tip/${USER_ID}"
```

Expected result:

```text
401 Unauthorized
```

### Internal route remains internally protected

Without the internal token:

```bash
curl -i -X POST \
  "${NUTRITION_AI_URL}/internal/api/v1/ai/proactive-tips/run?period=NOON"
```

Expected result:

```text
403 Forbidden
```

With the internal token:

```bash
curl -i -X POST \
  -H "X-Internal-Token: ${NUTRITION_AI_INTERNAL_TOKEN}" \
  "${NUTRITION_AI_URL}/internal/api/v1/ai/proactive-tips/run?period=NOON"
```

Expected result: `202 Accepted` if downstream/domain dependencies are ready, otherwise a domain/runtime error after the internal token is accepted.

## IoT service Auth0, legacy, and device API key checks

`iot-service` has two authentication surfaces:

- Management/query endpoints use Auth0 or legacy JWT.
- Device ingestion endpoints keep the existing `X-API-Key` flow.

Permissions:

```text
read:iot
write:iot
```

```bash
GATEWAY_URL="http://localhost:8080"
IOT_URL="http://localhost:8091"
USER_ID="1"
DEVICE_ID="REPLACE_WITH_DEVICE_ID"
DEVICE_API_KEY="REPLACE_WITH_DEVICE_API_KEY"
```

### Auth0 token through Gateway

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_IOT}" \
  "${GATEWAY_URL}/api/v1/iot/devices/${USER_ID}"
```

Expected result: valid auth. A domain-level `200`, `400`, or `404` can be valid depending on local data, but the response must not be `401` or `403`.

### Auth0 token direct to iot-service

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_READ_IOT}" \
  "${IOT_URL}/api/v1/iot/devices/${USER_ID}"
```

Expected result: direct service accepts issuer, audience, and `read:iot`.

### Missing read:iot permission

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WITHOUT_IOT}" \
  "${GATEWAY_URL}/api/v1/iot/devices/${USER_ID}"
```

Expected result:

```text
403 Forbidden
```

### Wrong audience rejection

```bash
curl -i -H "Authorization: Bearer ${AUTH0_TOKEN_WRONG_AUDIENCE}" \
  "${GATEWAY_URL}/api/v1/iot/devices/${USER_ID}"
```

Expected result:

```text
401 Unauthorized
```

### Legacy token compatibility

With `LEGACY_JWT_ENABLED=true` and `LEGACY_JWKS_ENABLED=true`:

```bash
curl -i -H "Authorization: Bearer ${LEGACY_TOKEN}" \
  "${GATEWAY_URL}/api/v1/iot/devices/${USER_ID}"
```

Expected result: gateway and `iot-service` accept the legacy token during migration.

### Missing token on management endpoint

```bash
curl -i "${GATEWAY_URL}/api/v1/iot/devices/${USER_ID}"
```

Expected result:

```text
401 Unauthorized
```

### Register device requires write:iot

```bash
curl -i -X POST \
  -H "Authorization: Bearer ${AUTH0_TOKEN_WRITE_IOT}" \
  -H "Content-Type: application/json" \
  --data '{}' \
  "${GATEWAY_URL}/api/v1/iot/devices"
```

Expected result: valid auth, then domain validation response. A token without `write:iot` must return `403`.

### Device ingestion still uses X-API-Key

Hydration:

```bash
curl -i -X POST \
  -H "X-API-Key: ${DEVICE_API_KEY}" \
  -H "Content-Type: application/json" \
  --data '{}' \
  "${GATEWAY_URL}/api/v1/iot/hydration"
```

Weight:

```bash
curl -i -X POST \
  -H "X-API-Key: ${DEVICE_API_KEY}" \
  -H "Content-Type: application/json" \
  --data '{}' \
  "${GATEWAY_URL}/api/v1/iot/weight"
```

Expected result: valid API key passes authentication. The request can still fail domain validation if the body is incomplete.

Without API key:

```bash
curl -i -X POST \
  -H "Content-Type: application/json" \
  --data '{}' \
  "${GATEWAY_URL}/api/v1/iot/hydration"
```

Expected result:

```text
401 Unauthorized
```

## Explicit audience rejection check

Use an Auth0 token from the same tenant but minted for a different API audience.

```bash
curl -i \
  -H "Authorization: Bearer ${AUTH0_ACCESS_TOKEN_WITH_WRONG_AUDIENCE}" \
  https://jameofit.duckdns.org/api/v1/users
```

Expected result:

```text
401 Unauthorized
```

## Legacy JWT compatibility check

With `LEGACY_JWT_ENABLED=true` and `LEGACY_JWKS_ENABLED=true`:

```bash
LEGACY_TOKEN="$(
  curl -fsS \
    -X POST https://jameofit.duckdns.org/api/v1/authentication/sign-in \
    -H 'Content-Type: application/json' \
    --data '{"username":"LEGACY_USER","password":"LEGACY_PASSWORD"}' \
  | jq -r '.token'
)"

curl --fail-with-body -i \
  -H "Authorization: Bearer ${LEGACY_TOKEN}" \
  https://jameofit.duckdns.org/api/v1/users
```

Expected result:

- Gateway accepts the legacy token while `LEGACY_JWT_ENABLED=true`.
- Legacy IAM JWKS remains available while `LEGACY_JWKS_ENABLED=true`.
- IAM allows the request only if the legacy user has `ROLE_ADMIN`.

## Legacy JWKS flag check

With `LEGACY_JWKS_ENABLED=false`, restart `config-service`, `iam-service`, and `gateway-service`, then run:

```bash
curl -i https://jameofit.duckdns.org/api/v1/jwks/.well-known/jwks.json
```

Expected result:

```text
404 Not Found
```

## Legacy sign-in flag check

With `LEGACY_JWT_ENABLED=false`, restart `config-service`, `iam-service`, and `gateway-service`, then run:

```bash
curl -i \
  -X POST https://jameofit.duckdns.org/api/v1/authentication/sign-in \
  -H 'Content-Type: application/json' \
  --data '{"username":"LEGACY_USER","password":"LEGACY_PASSWORD"}'
```

Expected result:

```text
404 Not Found
```
