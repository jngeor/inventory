# ADR-0027: Agent de OpenTelemetry para instrumentar y alertas gestionadas por Grafana

* **Estado**: Aceptado
* **Fecha**: 2026-11-15
* **Ticket**: KOAL-11
* **Amplía y corrige**: ADR-0014, en cómo se instrumentan los servicios y quién evalúa las alertas.

## Contexto

ADR-0014 fija el stack (OpenTelemetry, Collector, Tempo, Loki, Prometheus y Grafana), pero deja dos cosas abiertas o en conflicto:

* **Cómo se instrumentan los servicios.** El C4 (nivel 2b) dice "OpenTelemetry Java agent / SDK". Los servicios son reactivos (WebFlux, R2DBC, MongoDB reactivo, Kafka), y en código reactivo el contexto de la traza no viaja por el hilo. ADR-0014 ya señala el riesgo: si `OutboxEventPublisher` no encuentra el contexto, la columna `traceparent` queda vacía sin dar error, y la traza se corta en Kafka (quality-attributes O1).
* **Quién evalúa las alertas y quién avisa.** ADR-0014 dice que Prometheus evalúa las reglas, pero ADR-0009 dice que Grafana envía el correo de escalamiento de `SYNC_FAILURE`. Grafana no puede notificar reglas que evalúa Prometheus sin un Alertmanager entre medio.

## Decisión

* **Los servicios y el gateway se instrumentan con el agent de OpenTelemetry para Java**, que se agrega a la imagen y se activa con `-javaagent`. Sin código, instrumenta WebFlux, WebClient, Kafka, R2DBC, MongoDB y Reactor, propaga el contexto en código reactivo, pone el `traceId` en los logs y los exporta por OTLP.
* **Las métricas siguen en Micrometer**, con Prometheus leyendo `/actuator/prometheus`. El exportador de métricas del agent se apaga (`OTEL_METRICS_EXPORTER=none`) para no tener dos fuentes de la misma métrica.
* **Las alertas las gestiona Grafana.** Las reglas, los puntos de contacto y las políticas de notificación se versionan en el repo como archivos de provisioning. Grafana evalúa las reglas contra Prometheus y envía el correo por SMTP; en local llega a Mailpit.
* **Prometheus guarda las métricas y no evalúa alertas.** Esto corrige ADR-0014.
* El detalle está en `docs/strategies/observability.md`.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Micrometer Tracing con el puente a OpenTelemetry** | Es el camino nativo de Spring, pero exige activar a mano la propagación de contexto en Reactor y la observación de Kafka, y R2DBC necesita un proxy aparte. Exportar los logs por OTLP necesita además su propio appender. Cada servicio podría olvidar una pieza, y el fallo es silencioso. |
| **SDK de OpenTelemetry instrumentado a mano** | Da el mayor control, pero multiplica el código de instrumentación en cuatro servicios. |
| **Prometheus evalúa y Alertmanager notifica** | Es el modelo clásico, pero suma un componente más al stack local, y el panel de alertas quedaría repartido entre Grafana y Alertmanager. |
| **Prometheus evalúa y Grafana solo muestra** | No hay quién envíe el correo de escalamiento que exige ADR-0009. |

## Consecuencias

**Positivas**
* El contexto de la traza viaja en el código reactivo sin depender de que cada servicio lo haga bien. Así se cierra el riesgo que ADR-0014 señalaba para la outbox.
* Agregar una librería que el agent ya instrumenta no requiere código de trazas.
* Las alertas, los dashboards y sus avisos se ven y se configuran en un solo lugar, versionado en el repo.

**Negativas / costos aceptados**
* Un JAR más por imagen, más tiempo de arranque y algo más de memoria.
* Hay menos control fino sobre qué se instrumenta. Lo que sobra se apaga por configuración (`OTEL_INSTRUMENTATION_<nombre>_ENABLED=false`).
* La versión del agent se actualiza aparte de Spring Boot, y una actualización puede cambiar nombres de spans o atributos. Se fija una versión y se actualiza a propósito.
* Si Grafana cae, no se evalúan las alertas. Ese caso lo debe cubrir la supervisión de la plataforma, igual que el de Inventario caído (ADR-0009).

**Cómo se verifica**: test de punta a punta de ADR-0014 (la petición HTTP y su mensaje en Kafka comparten el `traceId`, también cuando la escritura de la outbox ocurre dentro de una cadena reactiva); revisión de que cada regla de `quality-attributes.md` D3, O2, R3 y de ADR-0009 existe en el provisioning de Grafana y dispara un correo en Mailpit al forzar la condición.

## Referencias

* `docs/strategies/observability.md`
* `docs/architecture/c4-model.md`, nivel 2b
* `docs/architecture/quality-attributes.md` 6
* ADR-0009, ADR-0014
