# ADR-0004: CQRS solo en Inventario

* **Estado**: Aceptado
* **Fecha**: 2026-10-31
* **Ticket**: KOAL-1 (documentado en KOAL-4)

## Contexto

El README original planteaba "un servicio con CQRS". Al dividir en cuatro microservicios (ADR-0001) hubo que decidir dónde aplicarlo. CQRS con BD de lectura separada cuesta mucho: proyector, idempotencia, consistencia eventual, fallos de sincronización (política de DLQ en `docs/README.md` 3.1) y reconstrucción de proyecciones.

* **Inventario** tiene una necesidad real de lectura distinta de la escritura. El kardex es un reporte por producto y rango de fechas con **saldo acumulado**, y además hay que mostrar el stock con desglose por ubicación y las alertas activas. Calcular eso sobre el modelo de escritura en cada consulta no escala con el historial (quality-attributes R3).
* **Órdenes** consulta pedidos por cliente, estado y fechas, lo que se resuelve bien con índices sobre su propia BD.
* **Catálogo** es un CRUD.
* **Notificaciones** casi no tiene lecturas.

## Decisión

* **Solo Inventario aplica CQRS completo**: BD de escritura (PostgreSQL) + outbox + Debezium + Kafka + proyector + BD de lectura (MongoDB) con los modelos `KardexEntry`, `ProductStockView` y `ActiveAlertView` (`docs/README.md` 3.1, `domain-model.md`). Ambos lados viven en **el mismo microservicio**; no son dos desplegables.
* **Órdenes no aplica CQRS**: tiene una sola BD, pero **reutiliza el outbox + Debezium** para publicar sus eventos de forma confiable.
* **Catálogo y Notificaciones**: una BD, sin outbox (no publican eventos).
* Los eventos internos del CQRS de Inventario **no forman parte del lenguaje publicado**: pueden cambiar sin coordinar con otros servicios (context-map 5).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **CQRS en todos los servicios** | Paga la complejidad de la consistencia eventual y la sincronización donde no hay necesidad de lectura que lo justifique. |
| **Sin CQRS en ningún servicio** (kardex calculado en la consulta) | El saldo acumulado sobre todo el historial y los filtros por ubicación se vuelven lentos a medida que crece el kardex, y compiten con las escrituras en la misma BD. |
| **CQRS "ligero" en Inventario** (vistas materializadas en la misma BD PostgreSQL) | Más simple, pero acopla la carga de reportes a la BD transaccional y no ejercita el patrón completo, que es parte del objetivo del proyecto (`docs/vision.md` 5). Queda como plan B si la operación de dos BD resulta excesiva. |
| **Lado de lectura como microservicio aparte** | Partiría el contexto core en dos desplegables que comparten el mismo modelo. Mismo argumento que en ADR-0001 contra separar Stock y Kardex. |

## Consecuencias

**Positivas**
* Las consultas de kardex y stock leen documentos ya calculados (quality-attributes R3), sin cargar la BD de escritura.
* La complejidad del patrón queda contenida en el contexto core, que es donde está el valor.
* La BD de escritura sigue siendo la fuente de verdad: cualquier proyección se puede reconstruir desde ella (`RebuildProductProjection`).

**Negativas / costos aceptados**
* Consistencia eventual dentro de Inventario: lo recién escrito tarda en verse en las consultas (meta p95 < 1 s, quality-attributes R3).
* El orden por producto depende de la clave de partición (`productId`, `docs/README.md` 3.1). Si un evento falla, el producto queda `outOfSync` hasta que se reconstruya, con un plazo de 24 h (quality-attributes D4).
* Inventario opera dos motores de BD (PostgreSQL y MongoDB), y los equipos deben conocer ambos.

**Cómo se verifica**: escenarios R3 y D4 de `quality-attributes.md`; test de integración que compara el saldo proyectado con el `physicalStock` de la escritura.

## Referencias

* `docs/README.md` 3, 3.1, 4.5
* `docs/domain-model.md`, Inventario, "Modelos de lectura"
* `docs/architecture/quality-attributes.md` R3, D4
