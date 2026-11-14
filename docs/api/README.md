# Contratos de las APIs REST

Cada microservicio tiene su contrato OpenAPI en esta carpeta. Se escribe a mano, es la fuente de verdad y CI lo compara con el código (ADR-0021). Lo común a todos está en `common.yaml`, y este documento fija las reglas que deben seguir.

Las decisiones de fondo están en ADR-0019 (versión, errores) y ADR-0013 (seguridad).

## Archivos

| Archivo | Contenido |
|---|---|
| `common.yaml` | Seguridad, paginación, errores y tipos compartidos. |
| `<servicio>.yaml` | Contrato de `catalog`, `inventory`, `orders` y `notifications`. |
| `redocly.yaml` | Reglas del linter. |
| `events-common.yaml` | Envelope y headers comunes de los eventos. |
| `<servicio>.events.yaml` | Contrato AsyncAPI de los eventos que publica `orders` o `inventory` (ADR-0024). |
| `inventory-internal.events.yaml` | Eventos privados del CQRS de Inventario. No son parte del lenguaje publicado. |

Para validar, desde esta carpeta, en PowerShell:

```powershell
npx.cmd --yes @redocly/cli@1.25.0 lint
```

* Los contratos usan **OpenAPI 3.1**.
* Cada contrato declara `servers: [{ url: /api/v1/<servicio> }]`, y sus rutas no repiten ese prefijo. `orders` y `notifications` tienen un recurso con el mismo nombre del servicio: declaran `/api/v1`, y sus rutas empiezan por `/orders` y `/notifications` (ADR-0021).
* Un contrato reutiliza lo común con `$ref: 'common.yaml#/components/...'`. Copiar un esquema común está prohibido.

## Rutas y operaciones

* **Rutas** en inglés, plural y kebab-case: `/products`, `/units-of-measure`.
* **Campos y parámetros** en inglés y camelCase, con los nombres de `docs/glosario.md`.

| Operación | Método | Respuesta |
|---|---|---|
| Crear | `POST /products` | `201` con el recurso y el header `Location` |
| Consultar | `GET /products/{id}` | `200` |
| Listar | `GET /products` | `200` con `items` y `page` |
| Modificar | `PUT /products/{id}` | `200` con el recurso |
| Acción de negocio | `POST /orders/{id}/cancel` | `200` con el recurso |

* **Nada se borra por API**: los recursos se desactivan con una acción (`/activate`, `/deactivate`) y por eso no hay `DELETE`. El kardex tampoco se modifica (`docs/domain-model.md`).
* **Las transiciones de estado son acciones**, nunca un `PUT` con el estado nuevo: así cada una tiene su permiso y sus reglas.
* **No se usa `PATCH`.**

## Tipos

| Dato | Formato |
|---|---|
| Identificadores | `string`, `format: uuid` |
| Fecha y hora (`Instant`) | `string`, `format: date-time`, en UTC con `Z`: `2026-11-07T15:30:00Z` |
| Solo fecha (`LocalDate`) | `string`, `format: date`: `2026-11-07` |
| Cantidades | `Quantity` de `common.yaml`: siempre enteras |
| Enumeraciones | Mayúsculas con guion bajo: `ADJUSTMENT_IN` |

Un campo opcional sin valor se omite de la respuesta; no se envía como `null`.

## Listas

Toda lista que pueda crecer se pagina, con los parámetros `Page` y `Size` de `common.yaml` (página desde 0, 20 elementos por defecto y 100 como máximo). La respuesta siempre tiene esta forma:

```json
{
  "items": [],
  "page": { "page": 0, "size": 20, "totalElements": 0, "totalPages": 0 }
}
```

Los filtros son parámetros de consulta en camelCase, como `status` o `fromDate`. Un rango de fechas incluye ambos extremos.

## Errores

Todo error usa `application/problem+json`, con el esquema `Problem` y las respuestas de `common.yaml`. Incluye `code` y `traceId`. `title`, `detail` y los mensajes van en español; `code` no cambia y es lo que un cliente debe usar.

| Estado | Cuándo | `code` |
|---|---|---|
| `400` | Formato o validación de la entrada | `VALIDATION_ERROR`, con la lista `errors` |
| `401` | Sin token, vencido o inválido | `UNAUTHORIZED` |
| `403` | Sin el rol necesario | `FORBIDDEN` |
| `404` | No existe, o es un pedido ajeno para un `CUSTOMER` | `RESOURCE_NOT_FOUND` |
| `409` | Choca con el estado actual: dato duplicado, transición inválida o escritura concurrente | Propio del caso, como `ORDER_INVALID_TRANSITION` |
| `503` | Una dependencia no responde, como Catálogo con el circuito abierto | `DEPENDENCY_UNAVAILABLE` |

* Los códigos propios van en mayúsculas con guion bajo y empiezan por el recurso.
* Un error nunca incluye trazas de pila, SQL ni nombres internos.
* Un pedido ajeno responde exactamente lo mismo que uno inexistente (ADR-0013).

## Seguridad

* Toda operación exige `bearerAuth`, salvo que su contrato diga lo contrario.
* Cada operación indica sus roles con la extensión `x-roles`, por ejemplo `x-roles: [ADMIN]`. Hoy existen `ADMIN`, `OPERATOR`, `CUSTOMER` y `SERVICE` (ADR-0022, ADR-0023).
* `SERVICE` es el rol de las llamadas entre servicios, que usan su propio token (ADR-0022).
* El `customerId` nunca viaja en la petición: sale del `sub` del token, y solo existe si el pedido lo registró un `CUSTOMER`.
* Salud y métricas quedan fuera de estos contratos.

## Cambios

* Agregar un campo opcional o una operación no cambia la versión.
* Quitar o renombrar un campo, cambiar su tipo o volverlo obligatorio es incompatible: sube a `/api/v2` (ADR-0019).
* Todo cambio empieza por el YAML, en el mismo PR que el código (ADR-0021).

## Eventos

Los eventos siguen ADR-0024: AsyncAPI 3, payloads en JSON Schema y JSON en Kafka.

* Todo evento tiene `eventId`, `eventType`, `occurredAt` y sus datos en `data`, según `events-common.yaml`.
* Todo mensaje lleva el header `traceparent` y declara su clave de Kafka.
* Los consumidores ignoran los campos y los `eventType` que no conocen.
* Un cambio incompatible crea un evento nuevo, como `OrderRegisteredV2`, en el mismo topic.
* Cada mensaje indica quién lo consume en `x-consumers`.

Para validar, desde esta carpeta:

```powershell
npx.cmd --yes @asyncapi/cli validate orders.events.yaml
npx.cmd --yes @asyncapi/cli validate inventory.events.yaml
npx.cmd --yes @asyncapi/cli validate inventory-internal.events.yaml
```
