# ADR-0019: Contrato REST con OpenAPI, versión en la ruta y errores RFC 9457

* **Estado**: Aceptado
* **Fecha**: 2026-11-07
* **Ticket**: KOAL-4

## Contexto

Los servicios exponen APIs REST a los clientes, a través del gateway (ADR-0015), y Catálogo además atiende a Inventario y Órdenes. Hay que fijar cómo se describe el contrato, cómo evoluciona y cómo se informan los errores, para que los cuatro servicios se comporten igual desde Catálogo, que es el primero.

## Decisión

* **Cada servicio publica su contrato en OpenAPI**, generado desde el código con springdoc y guardado en `docs/api/`.
* **La versión va en la ruta, y cada servicio tiene su prefijo**: `/api/v1/catalog/...`, `/api/v1/inventory/...`, `/api/v1/orders/...` y `/api/v1/notifications/...`. El gateway enruta por ese prefijo.
* **La versión solo sube con un cambio incompatible.** Agregar un campo opcional o un endpoint no la cambia.
* **Los errores usan Problem Details (RFC 9457)**, con `application/problem+json`. Se agregan dos campos propios: `code`, estable y legible por máquina, y `traceId`, para diagnosticar (quality-attributes O1).
* **Un error no expone detalles internos.** Un pedido ajeno responde el mismo 404 que uno inexistente (ADR-0013).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Escribir primero el OpenAPI y generar el código** | Da un contrato más cuidado, pero agrega generación de código y una carga mayor con una sola persona. |
| **Versión en un header o en el media type** | Es más purista, pero más difícil de probar y de enrutar en el gateway. |
| **Sin versión** | Un cambio incompatible rompería a los clientes sin aviso. |
| **Formato de error propio** | Hay que definir y documentar algo que ya existe como estándar, y Spring lo soporta con `ProblemDetail`. |
| **GraphQL** | Sus ventajas no aplican a recursos simples con pocos clientes, y complica la autorización. |

## Consecuencias

**Positivas**
* Los clientes manejan los errores de los cuatro servicios de la misma forma.
* Un error reportado lleva el `traceId` con el que se encuentra su traza.
* Mantener dos versiones de una API se resuelve con dos prefijos.

**Negativas / costos aceptados**
* Al generarse desde el código, un cambio accidental también cambia el contrato. Hay que compararlo en CI con el guardado en `docs/api/`.
* Las anotaciones de springdoc solo pueden ir en los adaptadores web, para no ensuciar `domain` (ADR-0002).
* Cada servicio debe mapear sus excepciones a `code` estables.
* Los prefijos revelan cómo está dividido el sistema, y mover un recurso de servicio cambiaría su ruta.

**Cómo se verifica**: test de CI que compara el OpenAPI generado con el de `docs/api/`; tests de integración del formato de error; escenarios S1 y S2 de `quality-attributes.md`.

## Referencias

* `docs/architecture/c4-model.md`, nivel 3
* `docs/architecture/quality-attributes.md` O1, S1, S2
* ADR-0002, ADR-0013, ADR-0015
