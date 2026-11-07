# ADR-0005: Integrar Órdenes e Inventario con una saga coreografiada por eventos

* **Estado**: Aceptado
* **Fecha**: 2026-10-31 (estados `PENDING`/`RESERVED` añadidos el 2026-11-01)
* **Ticket**: KOAL-1 (documentado en KOAL-4)

## Contexto

Un pedido **siempre se registra**, haya o no stock (`docs/README.md` 2). La verificación y reserva de stock la hace Inventario, y su resultado cambia el estado del pedido en Órdenes. Como cada servicio tiene su propia BD (ADR-0003), no hay una transacción que abarque a los dos.

Necesitamos:

* que el cliente no espere a Inventario para registrar su pedido;
* que una caída de Inventario no impida registrar pedidos (quality-attributes D1);
* que ningún evento se pierda entre la BD y Kafka.

## Decisión

* **Órdenes e Inventario se coordinan solo por eventos en Kafka**, en una **saga coreografiada**, sin orquestador (`docs/README.md` 4.2). Órdenes publica `OrderRegistered`, `OrderProcessed`, `OrderCancelled` y `OrderReturned`. Inventario responde con `StockReserved` o `StockInsufficient`. Cada servicio reacciona a los eventos del otro.
* **Ninguno llama al otro de forma síncrona** (context-map, regla 4).
* **Los eventos se publican siempre vía outbox**, en la misma transacción que el cambio de estado, y Debezium los lleva a Kafka. El código de negocio nunca publica directo a Kafka (context-map, regla 7).
* **Consumidores idempotentes**: cada evento lleva un `eventId`; los duplicados y los eventos que llegan con el agregado en un estado incompatible se ignoran (`domain-model.md`, Órdenes).
* **Compensaciones**: cancelar libera la reserva o repone el stock según el `previousStatus`, y la expiración a 48 h cierra cualquier saga que no avance.
* **Relación DDD**: **Partnership** entre los dos contextos (context-map R3).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Llamada síncrona Órdenes → Inventario** al registrar | Acopla la disponibilidad de Órdenes a la de Inventario: si Inventario cae, no se registran pedidos, lo que contradice que el pedido siempre se registre. Además, el cliente esperaría la reserva. |
| **Saga orquestada** (un orquestador en Órdenes o aparte que da órdenes a Inventario) | Con dos participantes y un flujo corto, el orquestador agrega un componente y su estado sin simplificar nada. Se reconsidera si la saga crece (ej. pagos, envíos externos). |
| **Transacción distribuida (2PC / XA)** | No la soportan Kafka ni los stacks reactivos, bloquea recursos y acopla la disponibilidad de los participantes. |
| **Publicar a Kafka directo desde el código** (sin outbox) | Doble escritura: si falla Kafka después del commit, o la BD después de publicar, el pedido y el stock quedan inconsistentes. |
| **Outbox con relay por polling** en lugar de Debezium | Más latencia, carga de polling sobre la BD y coordinación entre instancias (`SKIP LOCKED`). Debezium soporta el patrón outbox de forma nativa (`docs/README.md` 3.1). |

## Consecuencias

**Positivas**
* Órdenes registra pedidos aunque Inventario esté caído; la saga sigue sola cuando vuelve (quality-attributes D1).
* Ningún evento se pierde entre la BD y Kafka (outbox + CDC, quality-attributes D3).
* Agregar un consumidor de los eventos de pedido no toca a Órdenes; así entró Notificaciones (context-map R4).

**Negativas / costos aceptados**
* Consistencia eventual: el pedido pasa por `REGISTERED` antes de `RESERVED` o `PENDING` (meta p95 < 2 s, quality-attributes R2).
* El flujo no está escrito en un solo lugar: se reparte entre los consumidores de los dos servicios. Lo compensan `docs/README.md` 4.2 y las trazas distribuidas (quality-attributes O1).
* Hay que implementar idempotencia, manejo de eventos fuera de orden y DLQ en cada consumidor.
* Cambiar el contrato de un evento exige coordinar a los dos socios (Partnership).

**Cómo se verifica**: escenarios D1, D3, R2 y O1 de `quality-attributes.md`; tests de contrato de los eventos entre Órdenes e Inventario; test de idempotencia (el mismo evento dos veces no crea una segunda reserva).

## Referencias

* `docs/README.md` 2, 2.1, 3.1, 4.2
* `docs/architecture/context-map.md` R3, sección 5 y reglas 4 y 7
* `docs/domain-model.md`, Inventario (`StockReservation`) y Órdenes (eventos)
