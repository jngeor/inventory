# ADR-0012: ShedLock para el scheduler de expiración

* **Estado**: Aceptado
* **Fecha**: 2026-11-01
* **Ticket**: KOAL-4

## Contexto

Órdenes cancela los pedidos no procesados a las 48 horas (`orders.expiration.timeout`, `expiresAt`). Lo hace un `@Scheduled` que dispara `ExpireOrders`. Con varias instancias de Órdenes, cada una dispararía el mismo job a la misma hora: varias tomarían los mismos pedidos y competirían por cancelarlos, o publicarían eventos duplicados.

## Decisión

* **`ExpirationScheduler` usa `@Scheduled` + ShedLock**, y solo la instancia que toma el candado ejecuta el job.
* **El candado vive en una tabla `shedlock` de la BD de cada servicio que lo usa**, sin infraestructura nueva. Se accede con el proveedor de R2DBC de ShedLock.
* **La purga del outbox (ADR-0006) usa el mismo mecanismo**, en Órdenes y en Inventario.
* **El candado tiene un tiempo máximo (`lockAtMostFor`) mayor que la duración esperada del job**, para que una instancia caída no lo retenga para siempre.
* **`ExpireOrders` sigue siendo seguro si corre dos veces**: las transiciones se validan contra el estado del pedido. ShedLock evita trabajo repetido; no es la única protección.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Sin coordinación** (confiar solo en el bloqueo optimista) | Evita cancelar dos veces, pero todas las instancias hacen el trabajo y generan conflictos en cada ejecución. |
| **Quartz en modo clúster** | Es más potente, pero agrega varias tablas y su propio modelo de jobs para una sola tarea periódica. |
| **`CronJob` de Kubernetes** | Sacaría el job del servicio y no existe en Docker Compose. |
| **Advisory locks de PostgreSQL** | Hay que escribir y mantener lo que ShedLock ya resuelve. |
| **Una instancia dedicada al scheduler** | Es un punto único de fallo y otro tipo de despliegue. |

## Consecuencias

**Positivas**
* Solución simple, sin infraestructura nueva, que permite escalar Órdenes horizontalmente.
* Si la instancia que tiene el candado cae, otra toma el job en una ejecución posterior.

**Negativas / costos aceptados**
* **El job debe terminar toda su cadena reactiva antes de devolver el control**: si dispara un `Mono` y vuelve, ShedLock libera el candado antes de terminar el trabajo. Hay que cubrirlo con un test.
* Si un job dura más que `lockAtMostFor`, otra instancia puede empezar en paralelo. El caso está cubierto porque `ExpireOrders` es seguro si corre dos veces.
* Una cancelación se retrasa hasta la siguiente ejecución del job: el plazo de 48 h no es exacto al segundo.

**Cómo se verifica**: test de integración con dos instancias del job sobre la misma BD, que comprueba que cada pedido vencido se cancela una sola vez y publica un solo `OrderCancelled`.

## Referencias

* `docs/domain-model.md`, Órdenes
* `docs/architecture/c4-model.md`, nivel 3 (`ExpirationScheduler`)
* `docs/architecture/quality-attributes.md` 8
* ADR-0011
