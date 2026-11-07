# ADR-0010: Ningún reintento es infinito

* **Estado**: Aceptado
* **Fecha**: 2026-11-01
* **Ticket**: KOAL-4

## Contexto

El sistema reintenta en varios puntos: consumidores de Kafka, Debezium, llamadas a Catálogo y proveedores de email y SMS. Un reintento sin límite esconde el fallo, bloquea particiones y consume recursos. Varios valores por defecto son peligrosos: en Debezium, `errors.max.retries` es `-1`, es decir, infinito. Además, si dos capas reintentan la misma operación, los intentos se multiplican.

## Decisión

* **En ningún punto del sistema hay reintentos infinitos.** Todo reintento tiene un máximo explícito.
* **Al agotarse, el mensaje o la operación termina en un destino visible**: DLQ, estado `FAILED`, alerta o métrica, para revisión manual.
* **Cada operación reintenta en una sola capa.** La excepción final de Resilience4j, incluido `CallNotPermittedException`, se clasifica como *not retryable* en el consumidor y va directo a la DLQ.
* **Los errores no recuperables** (deserialización, validación, regla de negocio) no se reintentan.
* **La DLQ solo se reprocesa a mano.**
* **Los valores se configuran por propiedades.** Los iniciales están en `docs/README.md` 5.1:

| Punto | Valor inicial |
|---|---|
| Consumidores de Kafka | 3 reintentos (1 s, 2 s, 4 s), luego DLQ |
| Debezium | `errors.max.retries=5` |
| Llamadas a Catálogo | Timeout 2 s, 2 reintentos, circuit breaker |
| Proveedores de email y SMS | Timeout 5 s, 3 reintentos, circuit breaker |

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Reintentar hasta que funcione** (consumidores o Debezium) | El fallo no se ve, y un mensaje con un error permanente bloquea su partición para siempre. |
| **Sin reintentos** | Cada fallo transitorio de red terminaría en la DLQ y exigiría trabajo manual. |
| **Topics de reintento con espera larga** (retry topics) | Agrega topics y rompe el orden por producto del que depende el kardex (ADR-0008). Se puede reconsiderar para consumidores que no dependan del orden. |
| **Reprocesar la DLQ automáticamente** | Reintroduce el ciclo de reintentos que esta decisión busca evitar. |
| **Reintentar en cada capa** | Con 3 reintentos en el consumidor sobre los de Resilience4j, una operación puede intentarse 12 veces. |

## Consecuencias

**Positivas**
* Todo fallo termina en un lugar visible y acotado en el tiempo.
* El tiempo máximo que un mensaje retiene su partición se puede calcular: 7 s en consumidores (quality-attributes D4).

**Negativas / costos aceptados**
* Una caída larga de una dependencia manda mensajes a la DLQ, y hay que reprocesarlos a mano.
* Hace falta una herramienta administrativa para reprocesar la DLQ.
* Los valores iniciales no están medidos: se ajustarán con las pruebas de los escenarios.

**Cómo se verifica**: escenarios D2, D3 y O2 de `quality-attributes.md`; test de configuración que falla si algún conector usa `errors.max.retries=-1`.

## Referencias

* `docs/README.md` 5.1
* ADR-0006, ADR-0008, ADR-0009
