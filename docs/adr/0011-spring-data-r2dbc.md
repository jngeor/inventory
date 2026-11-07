# ADR-0011: Spring Data R2DBC para la persistencia reactiva

* **Estado**: Aceptado
* **Fecha**: 2026-11-01
* **Ticket**: KOAL-4

## Contexto

Los cuatro microservicios usan WebFlux. Su modelo reactivo atiende muchas peticiones con pocos hilos, y una llamada bloqueante en esos hilos frena a todas las demás. JDBC y JPA son bloqueantes, así que no se pueden llamar directamente desde ese flujo.

## Decisión

* **La persistencia en PostgreSQL usa Spring Data R2DBC**, detrás de los puertos de salida (ADR-0002).
* **Las entidades de persistencia están separadas de las del dominio**, y el adaptador mapea entre ellas (c4-model, `R2dbcPersistenceAdapter`).
* **Las transacciones son reactivas.** El agregado y su fila del outbox se guardan en la misma (ADR-0005).
* **La BD de lectura de Inventario usa Spring Data MongoDB Reactive** (c4-model).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **JPA/Hibernate en un pool de hilos aparte** (`boundedElastic`) | Mantiene el bloqueo, solo lo mueve de lugar. El límite pasa a ser el pool, y la transacción no se integra con el flujo reactivo. |
| **Hibernate Reactive** | Conserva el ORM, pero se integra menos con Spring Data y suma un modelo de sesión propio. |
| **Spring MVC con JDBC** (sin WebFlux) | Más simple, pero WebFlux es parte del stack definido del proyecto (ADR-0017). |
| **jOOQ sobre R2DBC** | Buen SQL tipado, pero agrega generación de código y no hace falta para consultas por agregado. |

## Consecuencias

**Positivas**
* Toda la cadena es no bloqueante, desde la petición hasta la BD.
* R2DBC no trae carga perezosa ni caché de sesión, así que cada consulta es explícita.

**Negativas / costos aceptados**
* **R2DBC no mapea relaciones.** Un agregado con hijos, como `Order` y sus `OrderItem`, se guarda y se carga con código propio en el adaptador.
* **Las migraciones no corren sobre R2DBC.** Las herramientas habituales (Flyway, Liquibase) usan JDBC, así que cada servicio necesita además ese driver, solo para migrar al arrancar.
* El equipo debe evitar llamadas bloqueantes en el flujo reactivo; un error ahí no falla en compilación.
* La depuración es más difícil: las trazas de pila de Reactor no siguen el código de la aplicación.

**Cómo se verifica**: escenario R1 de `quality-attributes.md`; reglas de ArchUnit que mantienen R2DBC fuera de `domain` (c4-model); tests de persistencia con Testcontainers.

## Referencias

* `docs/architecture/c4-model.md`, nivel 3 y estructura de paquetes
* ADR-0002, ADR-0003, ADR-0005, ADR-0007
