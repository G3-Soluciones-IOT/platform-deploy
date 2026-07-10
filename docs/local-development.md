# Local Development

Esta guia levanta el entorno local definido en `docker/docker-compose.local.yml` usando imagenes Docker locales con tag `<service-name>:local`.

## Requisitos Previos

- Docker y Docker Compose disponibles en la terminal.
- Bash o PowerShell.
- Imagenes locales construidas para todos los servicios:
  - `config-service:local`
  - `eureka-service:local`
  - `gateway-service:local`
  - `iam-service:local`
  - `goals-service:local`
  - `meal-plans-service:local`
  - `payments-service:local`
  - `profiles-service:local`
  - `recipes-service:local`
  - `tracking-service:local`
  - `communication-service:local`
- Archivo `env/local.env` creado desde `env/local.env.example`.

## Servicios Y Puertos

| Servicio | Puerto local |
| --- | ---: |
| `gateway-service` | `8080` |
| `iam-service` | `8081` |
| `goals-service` | `8083` |
| `meal-plans-service` | `8084` |
| `payments-service` | `8092` |
| `profiles-service` | `8086` |
| `recipes-service` | `8087` |
| `tracking-service` | `8089` |
| `communication-service` | `8090` |
| `config-service` | `8888` |
| `eureka-service` | `8761` |

## Bases De Datos

Cada servicio de dominio con PostgreSQL usa un contenedor propio con PostgreSQL 17:

| Servicio | Contenedor |
| --- | --- |
| `iam-service` | `iam-service-postgres` |
| `goals-service` | `goals-service-postgres` |
| `meal-plans-service` | `meal-plans-service-postgres` |
| `payments-service` | `payments-service-postgres` |
| `profiles-service` | `profiles-service-postgres` |
| `recipes-service` | `recipes-service-postgres` |
| `tracking-service` | `tracking-service-postgres` |

`communication-service` usa MongoDB 7:

| Variable | Valor local |
| --- | --- |
| `MONGO_HOST` | `communication-service-mongodb` |
| `MONGO_PORT` | `27017` |
| `MONGO_DATABASE` | `communication_db` |
| `MONGO_AUTH_DB` | `admin` |

## Arranque Con Bash

```bash
cp env/local.env.example env/local.env
chmod +x scripts/*.sh
./scripts/local-up.sh
```

Validar el entorno:

```bash
./scripts/healthcheck.sh
```

Bajar sin borrar volumenes:

```bash
./scripts/local-down.sh
```

Bajar y borrar volumenes:

```bash
REMOVE_VOLUMES=true ./scripts/local-down.sh
```

## Arranque Con PowerShell

```powershell
Copy-Item env/local.env.example env/local.env
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\local-up.ps1
```

Validar el entorno:

```powershell
.\scripts\healthcheck.ps1
```

Bajar sin borrar volumenes:

```powershell
.\scripts\local-down.ps1
```

Bajar y borrar volumenes:

```powershell
$env:REMOVE_VOLUMES="true"; .\scripts\local-down.ps1; Remove-Item Env:\REMOVE_VOLUMES
```

## Orden De Arranque

`local-up` levanta el entorno por fases para reducir race conditions:

1. Bases de datos.
2. `config-service`.
3. `eureka-service`.
4. `iam-service`.
5. Servicios de dominio: `goals-service`, `meal-plans-service`, `payments-service`, `profiles-service`, `recipes-service`, `tracking-service`, `communication-service`.
6. `gateway-service`.

El script espera `/actuator/health` en cada servicio y valida el registro en Eureka para los servicios de aplicacion y gateway.

## Troubleshooting

**Falta una imagen `:local`**

`local-up` valida las imagenes antes de levantar contenedores. Si falla, construye la imagen faltante con el tag exacto `<service-name>:local`.

**Puerto ocupado**

Revisa que los puertos de la tabla no esten usados por otro proceso. Libera el puerto o ajusta temporalmente el valor `*_HOST_PORT` en `env/local.env`.

**Contenedor previo con el mismo nombre**

`local-up` remueve los contenedores locales conocidos antes de levantar. Si el conflicto persiste, revisa:

```bash
docker ps -a
docker logs -f <container-name>
```

**`config-service` no responde**

Verifica que existe `config-service:local` y revisa sus logs:

```bash
docker logs -f config-service
```

**`eureka-service` no responde**

Confirma que `config-service` ya esta healthy y revisa:

```bash
docker logs -f eureka-service
```

**Un servicio no se registra en Eureka**

Ejecuta el healthcheck y revisa el contenedor del servicio:

```bash
./scripts/healthcheck.sh
docker logs -f <container-name>
```

En PowerShell:

```powershell
.\scripts\healthcheck.ps1
docker logs -f <container-name>
```

**MongoDB no esta listo**

Revisa el estado y logs de `communication-service-mongodb`:

```bash
docker logs -f communication-service-mongodb
docker logs -f communication-service
```
