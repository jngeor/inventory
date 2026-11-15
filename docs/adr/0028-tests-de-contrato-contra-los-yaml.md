# ADR-0028: Los tests de contrato validan contra los YAML de `docs/api/`

* **Estado**: Aceptado
* **Fecha**: 2026-11-15
* **Ticket**: KOAL-11
* **Cierra**: el pendiente "Herramienta de tests de contrato" de `adr/README.md`.

## Contexto

Los contratos se escriben primero, a mano, y son la fuente de verdad: OpenAPI para REST (ADR-0021) y AsyncAPI con JSON Schema para los eventos (ADR-0024). Para REST ya hay un control: en CI, springdoc genera el contrato real del servicio y se compara con el YAML (ADR-0021).

Para los eventos no hay ninguno. Un productor puede publicar algo que no cumple su AsyncAPI, y un consumidor puede romperse con un campo nuevo. M3 (`quality-attributes.md`) exige que el productor y los consumidores pasen con la versión nueva de un evento y con la anterior, sin redesplegar a los consumidores.

Todo vive en un solo repositorio (ADR-0018), lo mantiene una sola persona, y los consumidores de cada evento ya están declarados en `x-consumers`.

## Decisión

* **No se usa una herramienta de contratos aparte.** Los tests validan contra los mismos YAML de `docs/api/`.
* **Productor de eventos**: un test de componente ejecuta cada caso de uso que publica, lee la fila de la outbox y valida su `payload` contra el JSON Schema del mensaje en el AsyncAPI del servicio, incluido el envelope de `events-common.yaml`. También valida `event_type` y `event_key` contra lo que declara el contrato.
* **Consumidor de eventos**: un test de componente consume cada ejemplo (`examples`) de los mensajes que el servicio declara en `x-consumers`, y también ese ejemplo con un campo desconocido agregado. Los dos deben procesarse sin error (M3).
* **REST**: se mantiene la comparación con springdoc de ADR-0021.
* **Cambios incompatibles**: en CI, un diff entre el YAML de la rama y el de `main` falla si un cambio es incompatible: `oasdiff` para OpenAPI y `asyncapi diff` para AsyncAPI. Un cambio incompatible exige `/api/v2` o un evento nuevo (ADR-0019, ADR-0024).
* El detalle está en `docs/strategies/testing.md`.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Pact** (contratos definidos por el consumidor) | Muestra qué usa realmente cada consumidor y soporta mensajes, pero es un segundo contrato paralelo a los YAML, y conviene un broker para compartirlo. Con un solo repo, duplica lo que ya está escrito. |
| **Spring Cloud Contract** (definido por el productor) | Genera stubs para los consumidores, pero su DSL vuelve a describir lo que ya dicen los YAML, y habría que mantener ambos iguales. |
| **Schema Registry con Avro o JSON Schema** | Valida en tiempo de ejecución, pero agrega un componente y cambia el formato de los eventos que fijó ADR-0024. |
| **Solo revisión manual** | No cumple M3: un cambio que rompe a un consumidor se descubriría en ejecución. |

## Consecuencias

**Positivas**
* El contrato tiene una sola fuente de verdad, la misma que se revisa en el PR (ADR-0021).
* Los ejemplos del AsyncAPI pasan a ser datos de prueba: un ejemplo mal escrito rompe el build.
* Un cambio incompatible se detecta antes del merge, no en ejecución.

**Negativas / costos aceptados**
* No se sabe qué campos usa cada consumidor: solo que acepta el contrato completo. Quitar un campo se trata siempre como incompatible, aunque nadie lo use.
* Los tests dependen de que los ejemplos del AsyncAPI cubran los casos importantes. Un mensaje necesita al menos un ejemplo por variante relevante, por ejemplo `OrderCancelled` desde `RESERVED` y desde `PROCESSED`.
* La compatibilidad con la versión anterior se prueba con el diff de los YAML, no con el código anterior desplegado.
* `oasdiff` y `asyncapi diff` pueden dar falsos positivos; la configuración se ajusta al implementar el primer servicio.

**Cómo se verifica**: escenario M3 de `quality-attributes.md`; el job de CI que corre el diff de los contratos; cada mensaje del AsyncAPI tiene su test de productor y uno de consumidor por cada servicio en `x-consumers`.

## Referencias

* `docs/strategies/testing.md`
* `docs/api/README.md`
* `docs/architecture/quality-attributes.md` M3
* ADR-0018, ADR-0019, ADR-0021, ADR-0024
