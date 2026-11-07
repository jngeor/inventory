# ADR-0018: Monorepo con Maven y un módulo por servicio

* **Estado**: Aceptado
* **Fecha**: 2026-11-07
* **Ticket**: KOAL-4

## Contexto

Antes de escribir el primer microservicio hay que decidir dónde vive el código y cómo se construye. El repositorio `inventory` ya contiene la documentación de todo el sistema (`docs/`), y hoy lo mantiene una sola persona. Los servicios deben poder desplegarse por separado (ADR-0001) y sin compartir dominio (context-map, reglas de los límites).

## Decisión

* **Un solo repositorio** contiene los servicios, el gateway y la documentación.
* **Maven con un POM padre y un módulo por desplegable**: `catalog`, `inventory`, `orders`, `notifications` y `gateway`.
* **El POM padre solo fija versiones y plugins.** No hay librería de dominio compartida.
* **Un módulo no depende de otro.** Los servicios se comunican por sus contratos (REST y eventos), no por código.
* **CI construye una imagen por servicio** y publica en GHCR solo lo que cambió (`docs/README.md` 5).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Un repositorio por servicio** | Da más independencia, pero con una sola persona multiplica la configuración de CI, las versiones y los cambios coordinados, sobre todo en la saga (Partnership, context-map R3). |
| **Gradle** | Es más rápido y flexible, pero sus scripts piden más mantenimiento. Maven alcanza para módulos convencionales. |
| **Librería común para eventos o dominio** | Acoplaría los despliegues y va contra las reglas de los límites. |

## Consecuencias

**Positivas**
* Un cambio que cruza servicios y documentación se revisa en un solo PR.
* Las versiones de Spring, Testcontainers y demás dependencias se alinean en un solo lugar.

**Negativas / costos aceptados**
* Estar en el mismo repositorio facilita saltarse los límites. Hay que vigilarlo: ningún módulo declara a otro como dependencia.
* CI debe detectar qué módulo cambió, para no construir todo en cada commit.
* Subir una versión en el POM padre afecta a todos los servicios a la vez.
* Si cada servicio pasa a tener su propio equipo, habría que separar el repositorio.

**Cómo se verifica**: revisión del POM de cada módulo; regla de CI que falla si un módulo depende de otro.

## Referencias

* `docs/README.md` 5
* `docs/architecture/context-map.md`, reglas de los límites
* ADR-0001, ADR-0002
