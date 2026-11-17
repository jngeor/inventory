# Visión del Proyecto — Gestión de Inventario (ProyectoKoala)

## 1. Problema

Controlar con precisión el inventario físico (stock, ubicaciones, kardex) y el ciclo de vida de los pedidos, evitando comprometer stock inexistente, detectando movimientos sospechosos que puedan indicar robo o pérdida, y manteniendo trazabilidad completa de cancelaciones y devoluciones.

## 2. Visión

Un sistema de gestión de inventario basado en microservicios que sea:

* **Correcto y auditable**: cada movimiento de stock, cambio de estado de un pedido o falla de sincronización queda registrado y es trazable (registro de incidencias, logs con traceId).
* **Resiliente**: el sistema sigue funcionando aunque algún componente falle, se recupera solo de los fallos temporales (reintentos, circuit breaker) y lo que no se resuelve queda visible en la DLQ para revisión manual.
* **Observable**: cualquier incidente — de negocio (stock mínimo, movimiento inusual) o técnico (fallo de sincronización) — es visible para el administrador casi en tiempo real.
* **Una referencia completa de arquitectura de microservicios en Java/Spring**: CQRS donde corresponde, eventos vía Kafka, seguridad centralizada, trazabilidad distribuida y un pipeline de CI/CD production-grade — también como ejercicio para probar estas prácticas de punta a punta.

## 3. Alcance

### Incluye
* Catálogo de productos.
* Inventario: guías de remisión, ubicaciones, traslados, kardex, bloqueo/liberación de stock.
* Pedidos: registro, verificación asíncrona de stock, procesamiento, envío, entrega, cancelación (automática a 48h o manual), devolución.
* Notificaciones al destinatario del pedido (SMS/email) ante cambios de estado del pedido.
* Alertas operativas para el administrador: stock mínimo, movimiento inusual, stock insuficiente, pedido cancelado, fallo de sincronización, ajuste de stock.
* Seguridad (Keycloak/OAuth2), trazabilidad (OpenTelemetry), logs centralizados, métricas (Prometheus/Grafana), resiliencia (circuit breaker, retries, DLQ), testing (Testcontainers, ArchUnit, contract tests), CI (GitHub Actions) y despliegue (Docker Compose, Kubernetes local).

### No incluye (por ahora)
* Pasarela de pagos o facturación electrónica real (el documento de compra asociado a una guía de remisión no se integra con un ente facturador externo).
* Multi-almacén o multi-sede.
* Lotes, vencimientos, ni conversión de unidades de medida.
* Frontend definitivo — se contempla un panel de administrador a futuro (con el apartado de alertas urgentes ya acordado), todavía no construido.

## 4. Usuarios / Stakeholders

El modelo de usuarios es **abierto/extensible**: hoy hay 3 roles de negocio, definidos en Keycloak (`docs/strategies/security.md` 2.2, ADR-0023). Un rol nuevo se agrega en el realm y en las operaciones que habilita, sin cambiar el modelo de seguridad.

El sistema no es necesariamente un e-commerce: también puede administrar un dark store. Por eso el usuario que opera y el destinatario del pedido son distintos (ADR-0023).

* **Administrador**: gestiona catálogo e inventario, ve el panel de alertas urgentes y los reportes de kardex.
* **Operador**: opera el día a día: registra guías, traslados y pedidos, y avanza los pedidos. No ajusta stock.
* **Cliente**: registra sus pedidos y los cancela antes de procesarlos. Los avisos los recibe el destinatario del pedido, que puede ser el mismo cliente o alguien sin cuenta (ADR-0023).
* *(futuros roles, por ejemplo almacenero u operador logístico, se agregan como roles del realm)*

## 5. Objetivos técnicos clave
* Arquitectura hexagonal (puertos y adaptadores) en cada microservicio.
* CQRS únicamente donde hay necesidad real de reportes (hoy, solo Inventario).
* Comunicación asíncrona vía Kafka para los flujos de negocio entre servicios (saga coreografiada); comunicación síncrona solo para consultas simples (ej. a Catálogo), con circuit breaker y retries.
* Patrón Outbox + Debezium (CDC) para publicar eventos de forma confiable sin perder consistencia entre BD y cola.

## 6. Criterios de éxito

Los criterios de éxito son los escenarios de calidad de `docs/architecture/quality-attributes.md`: cada uno tiene una medida y su forma de verificarla. El sistema cumple su propósito cuando se cumplen todos los de prioridad alta (A).
