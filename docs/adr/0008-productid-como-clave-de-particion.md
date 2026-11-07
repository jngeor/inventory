# ADR-0008: `productId` como clave de partición de los eventos de stock

* **Estado**: Aceptado
* **Fecha**: 2026-11-01
* **Ticket**: KOAL-4

## Contexto

El kardex guarda un **saldo acumulado**, así que el proyector debe aplicar los movimientos de cada producto en el orden en que ocurrieron. Kafka solo garantiza el orden dentro de una partición, y la partición depende de la clave del mensaje.

Por defecto, el Outbox Event Router usa `aggregateid` como clave. Eso no sirve aquí: los movimientos de un mismo producto salen de agregados distintos (`DeliveryNote`, `StockTransfer`, `StockReservation`, `StockAdjustment`) y terminarían en particiones distintas.

## Decisión

* **`StockMovementRecorded` y `ProductStockChanged` se publican con `productId` como clave.**
* La fila del outbox lleva esa clave en **una columna propia**, separada de `aggregateid`, y el Outbox Event Router la usa como clave del mensaje (`table.field.event.key`).
* **Todos los eventos del CQRS van a un solo topic**, `inventory.internal.events`. Si fueran a topics distintos no habría orden entre ellos (context-map 5).
* **El proyector procesa cada partición en secuencia**, sin paralelismo dentro de ella. Puede haber paralelismo entre particiones.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **`aggregateid` como clave** (el valor por defecto) | Reparte los movimientos de un producto en varias particiones y se pierde el orden. |
| **Topic de una sola partición** | Da orden total, pero limita todo el proyector a un solo consumidor y un producto lento frena a los demás. |
| **Sin clave, y reordenar en el proyector por secuencia o fecha** | Hay que retener eventos y detectar huecos: mucha lógica para algo que Kafka ya da. |
| **Calcular el saldo al consultar** | Desaparece la dependencia del orden, pero se vuelve al problema que motivó el CQRS (ADR-0004). |

## Consecuencias

**Positivas**
* El saldo acumulado de cada producto se calcula bien, sin lógica de reordenamiento.
* Varias instancias del proyector pueden repartirse las particiones con un consumer group.

**Negativas / costos aceptados**
* Todos los eventos de un producto muy activo caen en la misma partición y esta puede retrasarse.
* **Aumentar las particiones cambia a qué partición va cada clave** y rompe temporalmente el orden por producto. El número de particiones se fija antes de producción y, si cambia, hay que drenar el topic primero.
* Un evento que va a la DLQ deja un hueco en esa secuencia: ver ADR-0009.
* La clave debe llenarse en todas las filas del outbox. Los eventos sin `productId` usan el id de su propio agregado.

**Cómo se verifica**: escenario R3 de `quality-attributes.md`; test de integración que publica varios movimientos del mismo producto desde agregados distintos y comprueba el saldo final.

## Referencias

* `docs/README.md` 3.1
* `docs/architecture/context-map.md` 5
* ADR-0004, ADR-0006, ADR-0009
