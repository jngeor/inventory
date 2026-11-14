# ADR-0022: Cada servicio usa su propio token para llamar a otro

* **Estado**: Aceptado
* **Fecha**: 2026-11-07
* **Ticket**: KOAL-9

## Contexto

Inventario y Órdenes consultan Catálogo por REST. ADR-0013 exige un JWT válido en todo endpoint de negocio, pero no define qué token usa un servicio cuando llama a otro. Hay flujos sin usuario: cuando Inventario consume un evento y consulta el `minimumStock` de un producto, nadie inició sesión.

## Decisión

* **Cada servicio que llama a otro tiene su propio client en Keycloak** y obtiene su token con el flujo `client_credentials`. Hoy son Inventario y Órdenes.
* **Una llamada entre servicios siempre usa el token del servicio que llama**, también si la originó un usuario. El token del usuario no se reenvía.
* **Esos tokens llevan el rol `SERVICE`**, que los contratos declaran en `x-roles`. Cada operación habilita solo a quien la necesita.
* **El token se reutiliza hasta poco antes de vencer**, sin pedir uno por llamada.
* **El secreto de cada client llega por variables de entorno**, distinto por servicio y por entorno (ADR-0003).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Reenviar el token del usuario** | No sirve en los flujos sin usuario, así que igual haría falta otra solución. Además, tener dos caminos complica la autorización. |
| **Dejar sin autenticar las llamadas internas** | Va contra S1 (el 100 % de los endpoints de negocio exige token) y deja la seguridad en manos de la red. |
| **Clave compartida entre servicios** | Es un secreto más que rotar, sin vencimiento ni identidad por servicio. |
| **TLS mutuo** | Identifica bien a cada servicio, pero exige gestionar certificados, y no aprovecha Keycloak, que ya está en el stack. |

## Consecuencias

**Positivas**
* Catálogo aplica el mismo control a todas las llamadas, sin excepciones (ADR-0013).
* Cada llamada identifica al servicio que la hizo, lo que ayuda en la auditoría.
* Un secreto expuesto se revoca para un solo servicio.

**Negativas / costos aceptados**
* **Keycloak pasa a ser una dependencia de las llamadas entre servicios.** Si cae, el token vigente sirve hasta vencer, unos 5 minutos, y después esas llamadas fallan. Un fallo así se trata como cualquier otro error de la llamada (ADR-0010).
* Hay más configuración: un client y un secreto por servicio y por entorno.
* Catálogo no sabe qué usuario originó la llamada. Si hiciera falta, tendría que viajar aparte.

**Cómo se verifica**: escenarios S1 y D2 de `quality-attributes.md`; test de integración con Keycloak en Testcontainers que llama a Catálogo con un token de servicio y comprueba que un token sin el rol recibe 403.

## Referencias

* `docs/architecture/context-map.md` R1, R2, R5
* ADR-0003, ADR-0010, ADR-0013
