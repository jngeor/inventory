# ADR-0017: Java 21, Spring Boot y WebFlux como base de los microservicios

* **Estado**: Aceptado
* **Fecha**: 2026-10-31
* **Ticket**: KOAL-4

## Contexto

Los cuatro microservicios necesitan una base común. Debe ser una herramienta consolidada, flexible, robusta y segura, porque el sistema maneja stock y un kardex que debe ser auditable (`docs/vision.md` 2).

El sistema también debe integrarse con Kafka, Keycloak, OpenTelemetry y Resilience4j, y ser verificable con Testcontainers y ArchUnit (`docs/README.md` 5).

## Decisión

* **Los cuatro microservicios usan Java 21 y Spring Boot.**
* **La capa web es WebFlux**, con un flujo reactivo de punta a punta, incluida la persistencia (ADR-0011).
* **Se eligió WebFlux por ser una herramienta consolidada que da suficiente flexibilidad, y además es robusta y segura.** La decisión no se basa en una necesidad de carga: la meta actual es de 10 pedidos por segundo (quality-attributes R1).
* **El API Gateway usa la misma base** (ADR-0015).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Spring MVC con virtual threads de Java 21** | Es la alternativa más cercana: código más simple, depuración más fácil y JPA o JDBC disponibles, y soportaría la carga de R1. Se prefirió WebFlux, una herramienta consolidada en el modelo reactivo. Es el camino de salida si el costo reactivo resulta excesivo. |
| **Quarkus o Micronaut** | Arrancan más rápido y consumen menos memoria, pero tienen menos integraciones listas para este stack. |
| **Node.js o Go** | Abandonan el ecosistema Java y Spring, en el que se apoya todo el stack transversal. |

## Consecuencias

**Positivas**
* Spring Security, Spring Kafka, Spring Data y Resilience4j cubren todo el stack con integraciones maduras.
* Toda la cadena es no bloqueante, lo que da margen si la carga crece.
* Una sola base para los cuatro servicios y el gateway facilita pasar de uno a otro.

**Negativas / costos aceptados**
* El código reactivo es más difícil de escribir, leer y depurar que el imperativo.
* Obliga a usar R2DBC, sin las comodidades de JPA (ADR-0011).
* El contexto de las trazas no viaja por el hilo, y hay que tomarlo del contexto de Reactor (ADR-0014).
* Una llamada bloqueante en el flujo reactivo no falla en compilación y frena al servicio. Necesita pruebas y revisión.

**Cómo se verifica**: escenario R1 de `quality-attributes.md`; reglas de ArchUnit (c4-model); revisión de llamadas bloqueantes.

## Referencias

* `docs/README.md` 5
* `docs/vision.md` 2
* `docs/architecture/quality-attributes.md` R1
* ADR-0002, ADR-0011, ADR-0014, ADR-0015
