# ADR-0014: Stack de observabilidad con OpenTelemetry, Tempo, Loki, Prometheus y Grafana

* **Estado**: Aceptado
* **Fecha**: 2026-10-31 (Tempo y Loki confirmados en KOAL-4)
* **Ticket**: KOAL-4

## Contexto

Un pedido cruza HTTP, varios servicios, el outbox, Debezium y Kafka (quality-attributes O1). La saga no está escrita en un solo lugar (ADR-0005), así que diagnosticarla exige seguir una misma ejecución entre servicios. También se necesitan alertas operativas sobre conectores, DLT y circuitos (quality-attributes D3, O2, R3).

`docs/README.md` 5 dejaba abiertas dos opciones: Jaeger o Tempo, y Loki o ELK. Este ADR las cierra.

## Decisión

* **OpenTelemetry instrumenta los cuatro servicios.** Trazas y logs van por OTLP al **OpenTelemetry Collector**, que los reenvía.
* **Tempo** guarda las trazas y **Loki** los logs.
* **Prometheus** guarda las métricas y evalúa las reglas de alerta.
* **Grafana** es el único panel: correlaciona las tres señales por `traceId` y sus dashboards están versionados en el repo.
* **Los logs son JSON estructurado** e incluyen el `traceId`.
* **El `traceId` se propaga también por Kafka**, en el header `traceparent`. Quien publica es Debezium, que no conoce la traza de la petición, así que el contexto viaja por el outbox:
  * La tabla outbox tiene una columna `traceparent`.
  * `OutboxEventPublisher` guarda ahí el contexto de la traza actual al escribir la fila.
  * El Outbox Event Router lo pasa al header con `table.fields.additional.placement=traceparent:header`.
  * El consumidor continúa la misma traza al leer el header.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Jaeger** en lugar de Tempo | Es una opción sólida, pero exige más configuración para saltar de una traza a sus logs. Tempo se integra directamente con Grafana y Loki. |
| **ELK** en lugar de Loki | Elasticsearch indexa todo el contenido y consume mucha más memoria, algo costoso en una máquina de desarrollo. Las búsquedas se hacen por `traceId` y etiquetas, que es lo que Loki indexa. |
| **Instrumentación propia por proveedor** (sin OpenTelemetry) | Ata el código a un backend. Con OTLP, cambiar Tempo o Loki no toca los servicios. |
| **Servicio gestionado** (Datadog, Grafana Cloud) | Tiene costo y no corre en local. |
| **Tracing nativo de Debezium** (`ActivateTracingSpanContext`) | Debezium aparecería como un tramo propio, pero hay que agregar y configurar OpenTelemetry en la imagen de Kafka Connect. Es mucho costo para ver un solo salto. |
| **`traceId` en el cuerpo del evento** | Mezcla datos técnicos con el contrato de negocio, y el consumidor tendría que restaurar la traza a mano. |

## Consecuencias

**Positivas**
* Desde un `orderId` se llega a la traza completa y a sus logs (quality-attributes O1).
* Las herramientas de datos pueden cambiarse sin tocar los servicios, porque ellos solo hablan OTLP.

**Negativas / costos aceptados**
* Son cinco componentes más en el stack local, que suman consumo de memoria.
* Loki no indexa el contenido: una búsqueda por texto libre sin etiquetas es lenta.
* **Debezium no aparece como un paso de la traza**, solo como el tiempo entre la escritura en el outbox y la entrega de Kafka. Si está caído, la traza termina en el servicio que escribió, y la alerta de conector `FAILED` lo confirma (quality-attributes D3).
* **En código reactivo el contexto de la traza no viaja por el hilo**: `OutboxEventPublisher` debe tomarlo del contexto de Reactor. Si falla, la columna queda vacía sin dar error.
* La retención en desarrollo es limitada: trazas 7 días, logs 14 días y métricas 15 días, todos configurables. Las trazas superan las 48 h de vida de un pedido atascado. La de producción se decidirá cuando exista ese entorno.

**Cómo se verifica**: escenarios O1 y O2 de `quality-attributes.md`; un test de punta a punta que comprueba que una petición HTTP y su mensaje en Kafka comparten el mismo `traceId`.

## Referencias

* `docs/README.md` 5
* `docs/architecture/c4-model.md`, nivel 2b
* `docs/architecture/quality-attributes.md` 6
* ADR-0005, ADR-0006
