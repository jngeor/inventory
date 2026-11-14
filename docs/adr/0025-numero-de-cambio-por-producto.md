# ADR-0025: Número de cambio por producto en los eventos de stock

* **Estado**: Aceptado
* **Fecha**: 2026-11-07
* **Ticket**: KOAL-9
* **Amplía**: ADR-0007, en cómo se aplica cada evento dos veces sin daño.

## Contexto

ADR-0007 hace la proyección idempotente sin transacciones. `KardexEntry` se inserta con el id del movimiento, y `ProductStockChanged` lleva valores absolutos. Pero el desglose por ubicación de `ProductStockView` se arma sumando y restando los movimientos de cada ubicación. Si el proyector se cae entre aplicar un movimiento y registrarlo en el log de idempotencia, al reprocesarlo lo suma dos veces.

Además, hoy un evento perdido solo se detecta cuando va a la DLQ. Si se pierde de otra forma, nadie lo nota.

## Decisión

* **Cada producto tiene un número de cambio (`sequence`)**, guardado en `ProductStock`, que sube de 1 en 1 con cada evento de stock. Lo llevan `StockMovementRecorded` y `ProductStockChanged`.
* **Todo cambio que genera un evento de stock actualiza la fila de `ProductStock`**, también los traslados, aunque no cambien el stock total.
* **El proyector aplica un evento solo si su `sequence` es mayor que el último aplicado en ese producto**, con una sola actualización condicional sobre el documento del producto. Si el número ya se aplicó, lo descarta.
* **Si el número salta**, por ejemplo de 40 a 42, el proyector marca el producto `outOfSync` y genera `SYNC_FAILURE` (ADR-0009).
* **`RebuildProductProjection` deja el número igual al de la escritura.**

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Transacción en MongoDB** (modelo y log a la vez) | Descartada en ADR-0007: exige replica set. |
| **Cantidad absoluta por ubicación en cada evento** | El lado de escritura tendría que mantener el stock por ubicación, que es referencial y no es fuente de verdad. |
| **Usar `version` de `ProductStock`** | Un traslado no la cambia y un reintento de bloqueo optimista puede saltarla. Un número propio deja clara su función. |
| **Quitar el desglose por ubicación** | Es un dato útil para el operador y el reporte, y solo hace falta protegerlo. |

## Consecuencias

**Positivas**
* El desglose por ubicación también se puede aplicar dos veces sin daño.
* Un evento perdido se detecta solo, por el hueco en el número, aunque no haya llegado a la DLQ.
* Las escrituras sobre un mismo producto quedan en orden, incluidos los traslados.

**Negativas / costos aceptados**
* Una columna más en `ProductStock`, y los traslados escriben en esa fila.
* Más contención sobre productos con mucho movimiento.
* El número es interno: no se debe usar fuera de la proyección.

**Cómo se verifica**: escenario D4 de `quality-attributes.md`; test que aplica dos veces el mismo movimiento y comprueba el desglose; test que salta un número y comprueba la marca `outOfSync`.

## Referencias

* `docs/api/inventory-internal.events.yaml`
* `docs/domain-model.md`, Inventario
* ADR-0007, ADR-0008, ADR-0009
