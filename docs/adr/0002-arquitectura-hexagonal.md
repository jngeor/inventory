# ADR-0002: Arquitectura hexagonal (puertos y adaptadores) en cada microservicio

* **Estado**: Aceptado
* **Fecha**: 2026-10-31
* **Ticket**: KOAL-1 (documentado en KOAL-4)

## Contexto

Cada microservicio combina reglas de negocio no triviales (máquina de estados del pedido, reservas todo o nada, detección de movimientos inusuales) con mucha tecnología alrededor: WebFlux, R2DBC, Kafka, outbox, Resilience4j, Keycloak, schedulers.

Queremos que:

* las reglas se puedan probar sin levantar infraestructura;
* cambiar un proveedor o una tecnología no toque el dominio (quality-attributes M2);
* la estructura se pueda verificar automáticamente.

El README lo exige como requisito de software (`docs/README.md` 3).

## Decisión

Cada microservicio sigue la **arquitectura hexagonal**, con esta estructura de paquetes (`docs/architecture/c4-model.md`, nivel 3):

* `domain`: agregados, value objects y eventos de dominio. Sin Spring, sin Reactor, sin R2DBC ni Kafka.
* `application.port.in`: una interfaz por caso de uso.
* `application.port.out`: lo que el núcleo necesita del exterior (repositorios, catálogo, publicación de eventos, reloj).
* `application.service`: implementa los casos de uso; maneja la transacción y orquesta el dominio con los puertos de salida.
* `adapter.in.*` (web, kafka, scheduler) y `adapter.out.*` (persistence, catalog, outbox…): la tecnología.

Las dependencias apuntan siempre hacia el núcleo. **Los puertos de entrada son los casos de uso**: no hay una capa extra de "interactors".

`application` puede depender de Reactor (`Mono`/`Flux`), porque el stack es reactivo de punta a punta. Envolverlo en tipos propios no aportaría nada. `domain` no depende de Reactor.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Clean Architecture** (entidades, casos de uso, adaptadores de interfaz, frameworks) | Agrega una capa de "casos de uso / interactors" que en un proyecto Spring de este tamaño queda redundante con los puertos de entrada: dos nombres para lo mismo y más clases de paso. |
| **Arquitectura en capas clásica** (controller, service, repository) | El dominio termina dependiendo de la persistencia (entidades JPA/R2DBC como modelo de dominio) y de Spring. Probar las reglas exige infraestructura, y cambiar tecnología toca el negocio. |
| **Hexagonal "ligera"** (sin puertos de entrada, controllers llamando a servicios concretos) | Se pierde el contrato explícito de cada caso de uso y una regla verificable que impida a un adaptador saltarse la aplicación. |

## Consecuencias

**Positivas**
* El dominio se prueba con tests unitarios puros: transiciones de estado, reservas y bordes de 48 h (quality-attributes S3).
* Un proveedor o tecnología nueva es un adaptador nuevo (quality-attributes M2), y la ACL hacia Catálogo vive en un adaptador (context-map R2).
* La misma estructura en los 4 servicios hace que moverse entre ellos sea predecible.

**Negativas / costos aceptados**
* Más tipos que en capas: mapeo entre entidades de persistencia y de dominio, una interfaz por caso de uso y DTOs por adaptador.
* Catálogo es casi un CRUD y la hexagonal le queda grande. Se acepta por consistencia entre los servicios.
* Hay que vigilar que el dominio no termine "anémico", con toda la lógica en los servicios de aplicación.

**Cómo se verifica**: reglas de ArchUnit en CI, en cada servicio (`docs/architecture/c4-model.md`, nivel 3):
1. `domain` no depende de otros paquetes de la aplicación ni de Spring, Reactor, R2DBC o Kafka.
2. `application` depende solo de `domain` (y de Reactor), nunca de `adapter`.
3. Un adaptador de entrada usa solo `application.port.in`; los adaptadores no se llaman entre sí.
4. Solo `adapter.out.*` implementa `application.port.out`.

## Referencias

* `docs/README.md` 3
* `docs/architecture/c4-model.md`, nivel 3
* `docs/architecture/quality-attributes.md` M2, S3
