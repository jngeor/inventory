# Visión del Proyecto — Gestión de Inventario (ProyectoKoala)

## 1. Problema

Controlar con precisión el inventario físico (stock, ubicaciones, kardex) y el ciclo de vida de los pedidos, evitando comprometer stock inexistente, detectando movimientos sospechosos que puedan indicar robo o pérdida, y manteniendo trazabilidad completa de cancelaciones y devoluciones.

## 2. Visión

Un sistema de gestión de inventario basado en microservicios que sea:

* **Correcto y auditable**: cada movimiento de stock, cambio de estado de un pedido o falla de sincronización queda registrado y es trazable (registro de incidencias, logs con traceId).
* **Resiliente**: el sistema sigue funcionando y se recupera solo (reintentos, circuit breaker, DLQ) aunque algún componente falle temporalmente.
* **Observable**: cualquier incidente — de negocio (stock mínimo, movimiento inusual) o técnico (fallo de sincronización) — es visible para el administrador casi en tiempo real.
* **Una referencia completa de arquitectura de microservicios en Java/Spring**: CQRS donde corresponde, eventos vía Kafka, seguridad centralizada, trazabilidad distribuida y un pipeline de CI/CD production-grade — también como ejercicio para probar estas prácticas de punta a punta.

## 3. Alcance

### Incluye
* Catálogo de productos.
* Inventario: guías de remisión, ubicaciones, traslados, kardex, bloqueo/liberación de stock.
* Pedidos: registro, verificación asíncrona de stock, procesamiento, envío, entrega, cancelación (automática a 48h o manual), devolución.
* Notificaciones al cliente (SMS/email) ante cambios de estado del pedido.
* Alertas operativas para el administrador: stock mínimo, movimiento inusual, stock insuficiente, pedido cancelado, fallo de sincronización, ajuste de stock.
* Seguridad (Keycloak/OAuth2), trazabilidad (OpenTelemetry), logs centralizados, métricas (Prometheus/Grafana), resiliencia (circuit breaker, retries, DLQ), testing (Testcontainers, ArchUnit, contract tests), CI (GitHub Actions) y despliegue (Docker Compose, Kubernetes local).

### No incluye (por ahora)
* Pasarela de pagos o facturación electrónica real (el documento de compra asociado a una guía de remisión no se integra con un ente facturador externo).
* Multi-almacén o multi-sede.
* Lotes, vencimientos, ni conversión de unidades de medida.
* Frontend definitivo — se contempla un panel de administrador a futuro (con el apartado de alertas urgentes ya acordado), todavía no construido.

## 4. Usuarios / Stakeholders

El modelo de usuarios es **abierto/extensible**: hoy se identifican 2 roles, pero se espera que aparezcan más a medida que se defina el sistema de seguridad (Keycloak, sección 5) con sus roles y permisos.

* **Administrador**: gestiona catálogo e inventario, ve el panel de alertas urgentes y los reportes de kardex.
* **Cliente**: registra pedidos y recibe notificaciones de su estado.
* *(futuros roles a definir junto con el modelo de permisos de Keycloak — ej. almacenero, operador logístico, etc.)*

## 5. Objetivos técnicos clave
* Arquitectura hexagonal (puertos y adaptadores) en cada microservicio.
* CQRS únicamente donde hay necesidad real de reportes (hoy, solo Inventario).
* Comunicación asíncrona vía Kafka para los flujos de negocio entre servicios (saga coreografiada); comunicación síncrona solo para consultas simples (ej. a Catálogo), con circuit breaker y retries.
* Patrón Outbox + Debezium (CDC) para publicar eventos de forma confiable sin perder consistencia entre BD y cola.

## 6. Criterios de éxito

*(pendiente de definir)*
