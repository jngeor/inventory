# Registro de Decisiones de Arquitectura (ADR)

Cada ADR registra una decisión importante: el contexto, lo decidido, las alternativas descartadas y sus consecuencias. Una decisión aceptada no se edita: si cambia, se escribe un ADR nuevo que la **reemplaza**, y el anterior se marca como reemplazado.

* **Formato**: `NNNN-titulo-en-kebab-case.md`, a partir de `template.md`.
* **Idioma**: español, como el resto de la documentación de negocio. Los nombres de código van en inglés (`docs/glosario.md`).

## Índice

### Estructura del sistema

| ADR | Decisión | Estado | Fecha |
|---|---|---|---|
| [0001](0001-descomposicion-en-cuatro-microservicios.md) | Descomponer el sistema en cuatro microservicios por contexto acotado | Aceptado | 2026-10-31 |
| [0002](0002-arquitectura-hexagonal.md) | Arquitectura hexagonal en cada microservicio | Aceptado; excepción de `@Transactional` agregada en KOAL-11 | 2026-10-31 |
| [0003](0003-base-de-datos-por-servicio.md) | Cada microservicio es dueño exclusivo de su base de datos | Aceptado | 2026-10-31 |
| [0004](0004-cqrs-solo-en-inventario.md) | CQRS solo en Inventario | Aceptado | 2026-10-31 |
| [0005](0005-saga-coreografiada-ordenes-inventario.md) | Integrar Órdenes e Inventario con una saga coreografiada por eventos | Aceptado | 2026-10-31 |

### Tecnología y operación

| ADR | Decisión | Estado | Fecha |
|---|---|---|---|
| [0006](0006-debezium-como-relay-del-outbox.md) | Debezium (CDC) como relay del outbox | Aceptado | 2026-10-31 |
| [0007](0007-mongodb-para-lectura-postgresql-para-el-resto.md) | MongoDB para la lectura de Inventario y PostgreSQL para el resto | Aceptado; ampliado por ADR-0025 | 2026-11-01 |
| [0008](0008-productid-como-clave-de-particion.md) | `productId` como clave de partición de los eventos de stock | Aceptado | 2026-11-01 |
| [0009](0009-fallos-de-proyeccion-dejar-pasar-y-marcar.md) | Ante un fallo de proyección, dejar pasar y marcar | Aceptado | 2026-11-01 |
| [0010](0010-reintentos-acotados.md) | Ningún reintento es infinito | Aceptado | 2026-11-01 |
| [0011](0011-spring-data-r2dbc.md) | Spring Data R2DBC para la persistencia reactiva | Aceptado | 2026-11-01 |
| [0012](0012-shedlock-para-el-scheduler-de-expiracion.md) | ShedLock para el scheduler de expiración | Aceptado | 2026-11-01 |
| [0013](0013-keycloak-y-resource-servers.md) | Keycloak como proveedor de identidad y cada servicio como resource server | Aceptado; ampliado por ADR-0023 y ADR-0026 | 2026-10-31 |
| [0014](0014-stack-de-observabilidad.md) | Stack de observabilidad con OpenTelemetry, Tempo, Loki, Prometheus y Grafana | Aceptado; precisado por ADR-0027 | 2026-10-31 |
| [0015](0015-spring-cloud-gateway.md) | Spring Cloud Gateway como punto de entrada | Aceptado | 2026-11-07 |
| [0016](0016-kafka-como-broker-de-eventos.md) | Kafka como broker de eventos | Aceptado | 2026-10-31 |
| [0017](0017-java-21-spring-boot-y-webflux.md) | Java 21, Spring Boot y WebFlux como base de los microservicios | Aceptado | 2026-10-31 |
| [0018](0018-monorepo-con-maven.md) | Monorepo con Maven y un módulo por servicio | Aceptado | 2026-11-07 |
| [0019](0019-contrato-rest.md) | Contrato REST con OpenAPI, versión en la ruta y errores RFC 9457 | Aceptado; reemplazado en parte por ADR-0021 | 2026-11-07 |
| [0020](0020-flyway-para-migraciones.md) | Flyway para las migraciones de PostgreSQL | Aceptado | 2026-11-07 |
| [0021](0021-contrato-openapi-primero.md) | El contrato OpenAPI se escribe primero | Aceptado | 2026-11-07 |
| [0022](0022-tokens-entre-servicios.md) | Cada servicio usa su propio token para llamar a otro | Aceptado | 2026-11-07 |
| [0023](0023-operador-y-destinatario.md) | Rol de operador y destinatario separado del usuario | Aceptado | 2026-11-07 |
| [0024](0024-formato-de-eventos.md) | Contrato de eventos con AsyncAPI y JSON Schema | Aceptado | 2026-11-07 |
| [0025](0025-numero-de-cambio-por-producto.md) | Número de cambio por producto en los eventos de stock | Aceptado | 2026-11-07 |
| [0026](0026-acceso-controlado-a-kafka.md) | Acceso controlado a Kafka en vez de tokens en los eventos | Aceptado | 2026-11-15 |
| [0027](0027-agent-de-opentelemetry-y-alertas-en-grafana.md) | Agent de OpenTelemetry para instrumentar y alertas gestionadas por Grafana | Aceptado | 2026-11-15 |
| [0028](0028-tests-de-contrato-contra-los-yaml.md) | Los tests de contrato validan contra los YAML de `docs/api/` | Aceptado | 2026-11-15 |

### Pendientes

* Helm o Kustomize para el despliegue en kind (`docs/README.md` 5).
* Retención de los topics de Kafka (ADR-0016).
* Herramienta para reprocesar la DLQ (ADR-0010): se define al implementar Inventario.
* Registro de pedidos desde otros sistemas (ADR-0023).

### Fuera de alcance por ahora

* **Listado de traslados (`GET /stock-transfers`)**, decidido el 2026-11-14. El kardex ya muestra los `TRANSFER_OUT` y `TRANSFER_IN` por producto, fecha y ubicación, y `getStockTransfer` da el detalle de cada traslado. Un traslado no cambia el stock total, así que tiene menos riesgo que un ajuste, que sí tiene listado. Además, el saldo por ubicación está fuera de alcance. Agregar el endpoint después no rompe el contrato. Se reconsidera si entra el saldo por ubicación, si aparece un rol de bodeguero o si se pide auditar los traslados de un operador.
