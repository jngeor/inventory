# Registro de Decisiones de Arquitectura (ADR)

Cada ADR registra una decisión importante: el contexto, lo decidido, las alternativas descartadas y sus consecuencias. Una decisión aceptada no se edita: si cambia, se escribe un ADR nuevo que la **reemplaza**, y el anterior se marca como reemplazado.

* **Formato**: `NNNN-titulo-en-kebab-case.md`, a partir de `template.md`.
* **Idioma**: español, como el resto de la documentación de negocio. Los nombres de código van en inglés (`docs/glosario.md`).

## Índice

### Estructura del sistema

| ADR | Decisión | Estado | Fecha |
|---|---|---|---|
| [0001](0001-descomposicion-en-cuatro-microservicios.md) | Descomponer el sistema en cuatro microservicios por contexto acotado | Aceptado | 2026-10-31 |
| [0002](0002-arquitectura-hexagonal.md) | Arquitectura hexagonal en cada microservicio | Aceptado | 2026-10-31 |
| [0003](0003-base-de-datos-por-servicio.md) | Cada microservicio es dueño exclusivo de su base de datos | Aceptado | 2026-10-31 |
| [0004](0004-cqrs-solo-en-inventario.md) | CQRS solo en Inventario | Aceptado | 2026-10-31 |
| [0005](0005-saga-coreografiada-ordenes-inventario.md) | Integrar Órdenes e Inventario con una saga coreografiada por eventos | Aceptado | 2026-10-31 |

### Pendientes (tecnología y operación)

Decisiones ya tomadas y documentadas en `docs/`, que todavía no tienen su ADR:

* Debezium (CDC) como relay del outbox, en lugar de polling (`docs/README.md` 3.1). Hoy aparece como alternativa en ADR-0005.
* MongoDB como BD de lectura de Inventario y PostgreSQL para el resto.
* `productId` como clave de partición de los eventos de stock.
* Política ante fallos de proyección: dejar pasar, marcar `outOfSync` y resolver en 24 h.
* Política de reintentos acotados (`docs/README.md` 5.1).
* Spring Data R2DBC para la persistencia reactiva.
* ShedLock para el scheduler de expiración.
* Keycloak: cada servicio como resource server.
* Stack de observabilidad (OpenTelemetry, Tempo, Loki, Prometheus, Grafana).
* Tecnología del API Gateway (por decidir).
