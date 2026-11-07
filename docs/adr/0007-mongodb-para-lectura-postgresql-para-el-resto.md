# ADR-0007: MongoDB para la lectura de Inventario y PostgreSQL para el resto

* **Estado**: Aceptado
* **Fecha**: 2026-11-01
* **Ticket**: KOAL-4

## Contexto

ADR-0003 da a cada servicio su propia BD y ADR-0004 separa la lectura de la escritura en Inventario. Falta justificar los motores.

* Las BD transaccionales necesitan transacciones entre el agregado y su outbox, restricciones de unicidad, bloqueo optimista y un WAL que Debezium pueda leer (ADR-0006).
* La BD de lectura de Inventario guarda modelos ya calculados (`KardexEntry`, `ProductStockView` con desglose por ubicación, `ActiveAlertView`). Los consulta la API y solo los escribe el proyector.

## Decisión

* **PostgreSQL** para todas las BD transaccionales: Catálogo, Inventario escritura, Órdenes y Notificaciones.
* **MongoDB** para la BD de lectura de Inventario. Los modelos de lectura se guardan como documentos listos para consultar y el log de idempotencia vive en la misma BD (`docs/README.md` 3.1).
* Solo el proyector de Inventario escribe en MongoDB. La fuente de verdad sigue siendo PostgreSQL: cualquier documento se puede regenerar (`RebuildProductProjection`).
* **La proyección sigue siendo asíncrona y cada evento se puede aplicar dos veces sin dañar el resultado**, sin transacciones de varios documentos:
  * `KardexEntry` se inserta con el id del movimiento como `_id`. Si llega un duplicado, MongoDB lo rechaza y se ignora.
  * `ProductStockChanged` lleva valores absolutos, no diferencias, y `ProductStockView` los reemplaza.
  * `StockMovementRecorded` lleva el saldo acumulado por producto, calculado en el lado de escritura.
  * El `eventId` se registra en el log de idempotencia después de aplicar el evento. Si el proyector cae antes, reaplicarlo no causa daño.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **PostgreSQL también para lectura** (otra base, con tablas desnormalizadas o JSONB) | Era viable y evita un segundo motor, pero el desglose por ubicación encaja de forma natural en un documento, sin joins ni tablas auxiliares. |
| **Vistas materializadas en la BD de escritura** | Ya descartado en ADR-0004. |
| **Elasticsearch** | Pensado para búsqueda de texto, que aquí no se necesita. Es más pesado de operar en local. |
| **MongoDB también para escritura** | Pierde las restricciones relacionales, y el conector de Debezium y el outbox tendrían que resolverse de otra forma. |
| **Transacción de varios documentos en el proyector** (modelo de lectura + log de idempotencia) | Exige correr MongoDB como replica set, también en desarrollo, y no hace falta si cada evento se puede aplicar dos veces sin daño. |

## Consecuencias

**Positivas**
* Cada consulta lee un documento ya calculado, sin joins (quality-attributes R3).
* El esquema de lectura puede cambiar sin migraciones: se reconstruye desde la escritura.

**Negativas / costos aceptados**
* Hay dos motores que operar, respaldar y monitorear.
* Los eventos de stock son más grandes: deben llevar valores absolutos y el saldo acumulado.
* El saldo acumulado por ubicación queda fuera del alcance por ahora. Si se agrega, y lo calcula el proyector, tendrá que reemplazar el valor en vez de sumarlo.
* Cada servicio que use PostgreSQL y MongoDB necesita los dos adaptadores de persistencia: hoy solo Inventario.

**Cómo se verifica**: escenario R3 de `quality-attributes.md`; test de integración que compara el saldo proyectado con el `physicalStock` de la escritura (ADR-0004).

## Referencias

* `docs/README.md` 3.1
* `docs/domain-model.md`, Inventario, "Modelos de lectura"
* ADR-0003, ADR-0004, ADR-0006
