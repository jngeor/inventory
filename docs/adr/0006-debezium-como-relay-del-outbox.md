# ADR-0006: Debezium (CDC) como relay del outbox

* **Estado**: Aceptado
* **Fecha**: 2026-10-31
* **Ticket**: KOAL-4

## Contexto

Inventario y Órdenes escriben sus eventos en una tabla outbox, en la misma transacción que el cambio de estado (ADR-0005). Falta decidir qué componente lleva esas filas a Kafka. Ese componente es el que define la latencia de la saga y del lado de lectura (quality-attributes R2, R3) y debe tolerar varias instancias de cada servicio sin publicar en desorden.

## Decisión

* **Debezium lee el WAL de PostgreSQL y publica en Kafka** con su **Outbox Event Router**, sobre Kafka Connect (`docs/README.md` 3.1).
* **Un conector por base con outbox** (Inventario escritura y Órdenes), cada uno con su slot de replicación y un usuario con permiso de replicación (ADR-0003).
* **El código de negocio solo escribe en la tabla outbox.** No conoce Kafka ni a Debezium (context-map, regla 7).
* **El Outbox Event Router elige el topic** según `aggregatetype` (context-map 5).
* **`errors.max.retries=5`**: el valor por defecto de Debezium es `-1`, que significa infinito, y debe sobrescribirse (ADR-0010).
* **Un job en Inventario y Órdenes borra las filas del outbox con más de 7 días** (valor configurable), protegido con ShedLock (ADR-0012). Borrar no pierde eventos, porque Debezium lee el WAL y no la tabla.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Relay por polling** dentro de cada servicio | Más latencia y carga constante sobre la BD. Con varias instancias hay que coordinar el poller (`SELECT ... FOR UPDATE SKIP LOCKED`), lo que puede alterar el orden de publicación. |
| **Polling con un proceso aparte** | Evita la concurrencia entre instancias, pero sigue con la latencia y la carga, y hay que escribir y operar ese proceso. |
| **Conector JDBC Source de Kafka Connect** | Exige el mismo despliegue de Kafka Connect, pero también lee por polling y no trae el enrutamiento del patrón outbox. |
| **Publicar a Kafka desde el código** | Doble escritura; ya descartado en ADR-0005. |
| **Borrar cada fila del outbox apenas se inserta** | Es posible, pero se pierden los conteos de la verificación de D3 y el rastro para diagnosticar. |

## Consecuencias

**Positivas**
* Baja latencia, sin consultas periódicas sobre la tabla outbox.
* El WAL conserva el orden de los commits, y publicar no depende de cuántas instancias tenga cada servicio.
* Si el conector falla, los eventos no se pierden: siguen en el outbox y en el WAL (quality-attributes D3).

**Negativas / costos aceptados**
* Hay más infraestructura que operar: Kafka Connect, conectores y slots de replicación.
* Requiere `wal_level=logical` en las BD con outbox (ADR-0003).
* **Un conector detenido retiene WAL**: su slot impide que PostgreSQL lo libere y el disco crece hasta que se reinicie. Por eso el estado `FAILED` del conector debe alertar (quality-attributes D3).
* La purga es un job más que operar en dos servicios.

**Cómo se verifica**: escenarios D3, R2 y R3 de `quality-attributes.md`; test de integración con Testcontainers que escribe en el outbox y lee el evento en Kafka, y que comprueba que borrar una fila no publica ningún mensaje.

## Referencias

* `docs/README.md` 3.1, 5.1
* `docs/architecture/context-map.md` 5 y regla 7
* ADR-0003, ADR-0004, ADR-0005
