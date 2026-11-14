# ADR-0024: Contrato de eventos con AsyncAPI y JSON Schema

* **Estado**: Aceptado
* **Fecha**: 2026-11-07
* **Ticket**: KOAL-9

## Contexto

Los servicios se coordinan por eventos en Kafka (ADR-0005, ADR-0016), y hasta ahora ningún documento fija su formato. `context-map.md` lista los eventos y sus datos principales, pero no su estructura exacta, y el formato quedó pendiente en `docs/api/`.

Cambiar un evento exige coordinar a quienes lo usan, y un mensaje incompatible termina en la DLQ (quality-attributes M3). El contrato debe describir también lo que rodea al mensaje: topic, clave y headers.

## Decisión

* **El contrato de eventos se escribe en AsyncAPI 3, y los payloads en JSON Schema.** Son archivos YAML a mano en `docs/api/`, y son la fuente de verdad, igual que los OpenAPI (ADR-0021).
* **Cada servicio que publica tiene su contrato.** El topic privado `inventory.internal.events` va en un archivo aparte, porque no forma parte del lenguaje publicado (ADR-0004).
* **Los eventos viajan en Kafka como JSON**, sin Schema Registry.
* **Todo evento tiene un envelope común**: `eventId` (UUID), `eventType` y `occurredAt` (UTC), y sus datos propios en `data`.
* **El contrato declara por cada topic su clave y sus headers**, incluido `traceparent` (ADR-0008, ADR-0014).
* **Los eventos de pedido y de reserva usan `orderId` como clave**, así los de un mismo pedido llegan en orden. En los de reserva es una excepción a ADR-0008, que asigna a los eventos sin `productId` el id de su agregado: cada pedido tiene una sola reserva, y `orderId` es el dato que Órdenes ya conoce.
* **Agregar un campo opcional es compatible.** Los consumidores ignoran los campos que no conocen y los `eventType` que no les interesan: eso no es un error ni va a la DLQ.
* **Un cambio incompatible crea un evento nuevo**, como `OrderRegisteredV2`, en el mismo topic. Ambos conviven hasta que todos los consumidores migren.
* **CI valida los contratos, comprueba los ejemplos contra los esquemas y compara con la versión anterior** para detectar cambios incompatibles.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Avro con Schema Registry** | El registro rechaza cambios incompatibles y los mensajes son más compactos. Pero suma un contenedor crítico, los mensajes binarios son difíciles de leer en la DLT y exige más configuración en Debezium y en los consumidores. Con 10 pedidos por segundo (quality-attributes R1), el tamaño no pesa. Es el camino si aparecen más equipos o consumidores externos. |
| **Protobuf con Schema Registry** | Tiene los mismos costos de Avro, y además generación de código. |
| **Solo JSON Schema, sin AsyncAPI** | Topics, claves y headers quedarían sin contrato. |
| **Sin contrato formal** (solo tests de contrato) | Haría que la estructura de los eventos viva solo en el código. Con Partnership (context-map R3) hace falta un acuerdo explícito. |

## Consecuencias

**Positivas**
* Los eventos y las APIs REST se definen, revisan y cambian de la misma forma.
* Los mensajes se pueden leer directamente, también en la DLT, lo que facilita diagnosticar (quality-attributes O2).
* No se agrega ningún contenedor.

**Negativas / costos aceptados**
* **Nada frena un cambio incompatible al publicar**: la protección depende de CI y de los tests de contrato.
* Los mensajes JSON son más grandes y su lectura más lenta que en un formato binario.
* El outbox guarda el evento como JSON, y Debezium debe publicarlo tal cual. Se debe confirmar con un test al configurar el conector.
* Hay una herramienta más que correr: `@asyncapi/cli`.
* Las herramientas de AsyncAPI son menos maduras que las de OpenAPI.

**Cómo se verifica**: escenario M3 de `quality-attributes.md`; validación de los contratos y sus ejemplos en CI; tests de contrato entre Órdenes e Inventario.

## Referencias

* `docs/api/`
* `docs/architecture/context-map.md` 5
* `docs/architecture/quality-attributes.md` M3, O2
* ADR-0004, ADR-0005, ADR-0006, ADR-0008, ADR-0014, ADR-0016, ADR-0021
