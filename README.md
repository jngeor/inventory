# ProyectoKoala: inventario y kardex

Sistema de gestión de inventario y reportes de kardex, formado por cuatro microservicios (**Catálogo**, **Inventario**, **Órdenes** y **Notificaciones**) detrás de un API Gateway. Está hecho en Java 21 con Spring Boot y WebFlux, con arquitectura hexagonal, CQRS en Inventario y una saga coreografiada por eventos en Kafka.

## Estado

Por ahora el repositorio solo tiene la documentación. Los módulos de código, el entorno local y la CI se agregan con sus propios tickets.

## Documentación

| Documento | Contenido |
|---|---|
| [`docs/README.md`](docs/README.md) | Requisitos, máquina de estados del pedido, arquitectura y stack |
| [`docs/vision.md`](docs/vision.md) | Problema, alcance y usuarios |
| [`docs/glosario.md`](docs/glosario.md) | Lenguaje ubicuo: español en los documentos, inglés en el código |
| [`docs/domain-model.md`](docs/domain-model.md) | Modelo de dominio |
| [`docs/architecture/`](docs/architecture/) | Context map, atributos de calidad, modelo C4 y modelo de datos |
| [`docs/api/`](docs/api/) | Contratos OpenAPI y AsyncAPI |
| [`docs/adr/`](docs/adr/README.md) | Decisiones de arquitectura |
| [`docs/strategies/`](docs/strategies/) | Seguridad, observabilidad y testing |
| [`docs/conventions.md`](docs/conventions.md) | Convenciones del repositorio: ramas, commits, PR, formato y secretos |

## Cómo contribuir

Todo cambio sigue [`docs/conventions.md`](docs/conventions.md): una rama `feature/KOAL-N` desde `main`, un commit con formato `tipo(alcance): KOAL-N descripción` y un PR a `main`.
