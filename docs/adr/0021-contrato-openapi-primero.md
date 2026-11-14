# ADR-0021: El contrato OpenAPI se escribe primero

* **Estado**: Aceptado
* **Fecha**: 2026-11-07
* **Ticket**: KOAL-9
* **Reemplaza**: la parte de ADR-0019 que genera el contrato desde el código, y su prefijo para Órdenes y Notificaciones. El resto de ADR-0019 sigue vigente.

## Contexto

ADR-0019 decidió generar el OpenAPI desde el código con springdoc. Pero el contrato de los cuatro servicios se va a definir antes de implementarlos, y todavía no hay código del cual generarlo. Además, definirlo primero permite revisar la API completa antes de escribir controladores, y un consumidor puede usarla sin esperar a que el servicio exista.

Sigue haciendo falta asegurar que el código cumpla el contrato: un YAML escrito a mano puede quedar desactualizado sin que nadie lo note.

## Decisión

* **El YAML de `docs/api/` se escribe a mano y es la fuente de verdad** de cada servicio.
* **El código implementa el contrato.** Los controladores y sus DTOs se escriben a mano, sin generación de código.
* **Un cambio de API empieza por el YAML**, en el mismo PR que el código.
* **springdoc se mantiene solo para comparar.** En CI, el servicio arranca y genera su contrato real, y el build falla si no coincide con el YAML.
* **La comparación es por significado**: rutas, parámetros, esquemas y códigos de respuesta. Ignora el orden y las descripciones.
* **Las rutas no repiten el nombre del servicio.** Con el prefijo de ADR-0019 quedarían `/api/v1/orders/orders` y `/api/v1/notifications/notifications`. Esos dos servicios usan directamente `/api/v1/orders` y `/api/v1/notifications`, y sus demás recursos cuelgan de ahí, como `/api/v1/orders/incidents`. El gateway sigue enrutando por el mismo prefijo.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Generar el contrato desde el código** (ADR-0019) | Exige escribir el servicio antes de definir su API, y el contrato solo se puede revisar después. |
| **Generar interfaces y DTOs desde el YAML** (`openapi-generator`) | Detecta los desvíos al compilar, pero suma un plugin y su configuración, y el código generado puede ser incómodo con WebFlux. Los controladores son delgados (ADR-0002), así que escribirlos a mano cuesta poco. Se puede adoptar después sin cambiar el YAML. |
| **Sin comparación en CI** | Un YAML escrito a mano terminaría desactualizado. |

## Consecuencias

**Positivas**
* La API se revisa completa antes de implementarla.
* Consumidores y servicios pueden trabajar en paralelo contra el mismo YAML.
* El build no suma generación de código.

**Negativas / costos aceptados**
* Los desvíos se detectan en CI, no al compilar.
* Los DTOs se escriben a mano y hay que mantenerlos alineados con el YAML.
* springdoc no deduce todo por sí solo. Para comparar códigos de respuesta y errores, los controladores necesitan anotaciones, que siguen limitadas a los adaptadores web (ADR-0019).
* Comparar dos contratos puede dar diferencias falsas, y habrá que ajustar la comparación al implementar el primer servicio.

**Cómo se verifica**: test de CI que compara el contrato generado por springdoc con el YAML de `docs/api/`.

## Referencias

* `docs/api/`
* ADR-0002, ADR-0019
