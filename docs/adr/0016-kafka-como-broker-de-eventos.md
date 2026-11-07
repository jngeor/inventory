# ADR-0016: Kafka como broker de eventos

* **Estado**: Aceptado
* **Fecha**: 2026-10-31
* **Ticket**: KOAL-4

## Contexto

Los servicios se coordinan por eventos: la saga entre Órdenes e Inventario (ADR-0005), el CQRS de Inventario (ADR-0004) y los avisos de Notificaciones. Un evento perdido deja un pedido o un saldo inconsistente, así que el broker debe dar **seguridad sobre los mensajes**.

Además, el kardex necesita que los eventos de cada producto se apliquen en orden (ADR-0008), y un consumidor nuevo debe poder sumarse sin tocar al que publica (context-map R4).

## Decisión

* **Kafka es el único broker del sistema** para los eventos entre servicios y para el CQRS de Inventario.
* **Se eligió sobre RabbitMQ porque da más seguridad**: los mensajes quedan persistidos en un log y no desaparecen al consumirse.
* **Debezium publica a Kafka por medio de Kafka Connect** (ADR-0006).
* **Cada grupo de consumidores lleva su propio avance**, y cada topic tiene su DLT (ADR-0010).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **RabbitMQ** | Es más simple de operar, pero da menos seguridad para este caso: un mensaje consumido sale de la cola y no se puede volver a leer. Además, mantener el orden por producto con varios consumidores es más difícil, y Debezium no publica ahí por medio de Kafka Connect. |
| **Redis Streams** | Tiene un modelo parecido, pero sus garantías de persistencia dependen de cómo se configure Redis. |
| **Apache Pulsar** | Es comparable a Kafka, pero con más componentes y menos integración con Spring y Debezium. |
| **Solo PostgreSQL** (tablas como cola) | Evita un componente, pero acopla a los servicios a una BD común, contra ADR-0003. |

## Consecuencias

**Positivas**
* Los eventos se conservan después de consumirse, durante la retención del topic, lo que permite reprocesarlos o agregar consumidores nuevos.
* El orden por clave de partición es lo que permite calcular el saldo del kardex (ADR-0008).
* Spring Kafka trae el manejo de reintentos y DLT que usa ADR-0010.

**Negativas / costos aceptados**
* Es el componente más pesado de operar, junto con Kafka Connect, y consume bastante memoria en una máquina de desarrollo.
* **Kafka se vuelve un punto crítico**: si cae, los eventos esperan en el outbox, pero las sagas y las proyecciones no avanzan.
* El número de particiones no se puede cambiar libremente sin afectar el orden (ADR-0008).
* Con un solo broker en desarrollo no hay replicación. La seguridad real ante la caída de un broker depende de la configuración de producción.
* Falta definir la retención de los topics.

**Cómo se verifica**: escenarios D1, D3, R2 y O2 de `quality-attributes.md`; tests de integración con Kafka real en Testcontainers.

## Referencias

* `docs/README.md` 3.1, 4.2, 5.1
* `docs/vision.md` 5
* `docs/architecture/context-map.md` 5
* ADR-0004, ADR-0005, ADR-0006, ADR-0008, ADR-0010
