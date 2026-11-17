# ADR-0026: Acceso controlado a Kafka en vez de tokens en los eventos

* **Estado**: Aceptado
* **Fecha**: 2026-11-15
* **Ticket**: KOAL-11
* **Amplía**: ADR-0013, en cómo se protegen los eventos.

## Contexto

ADR-0013 deja fuera de la validación de tokens a Kafka: los eventos no llevan token y "se confían por ser internos". Pero hoy nadie controla quién se conecta al broker, y los consumidores aplican lo que llega. Quien alcance Kafka por la red puede publicar en cualquier topic como si fuera Debezium.

El caso más grave es justo el fraude interno de S3 (`quality-attributes.md`):

* Un `OrderCancelled` falso con `previousStatus` = `PROCESSED`, sobre un pedido real ya procesado, hace que Inventario reponga stock con un movimiento `CANCELLATION`. No exige el rol `ADMIN`, no genera la alerta `STOCK_ADJUSTMENT`, y en Órdenes el pedido sigue `PROCESSED`. Un `OrderReturned` falso sobre un pedido `DELIVERED` hace lo mismo. Es una forma de encubrir un robo que esquiva el control del ajuste de stock.
* Los eventos de pedido llevan datos personales del destinatario (nombre, email, teléfono, dirección).
* Un `StockReserved` falso deja un pedido `RESERVED` sin stock.
* Con acceso de administración se pueden borrar topics o mover offsets, y la API REST de Kafka Connect permite reconfigurar el conector del outbox.

La validación de estado de los consumidores lo limita, porque un evento falso necesita un `orderId` real y una transición válida, pero no lo impide.

Poner el token del usuario en cada evento no lo resuelve. El token vence en 5 minutos, así que un evento reprocesado desde la DLQ horas después no se podría validar. Además, quien escribe el mensaje es Debezium, no el usuario, y un token capturado se puede reutilizar mientras no venza.

## Decisión

* **Los eventos siguen sin token.** El control va en el broker: quién se conecta y qué puede hacer cada uno.
* **En todos los entornos, Kafka y Kafka Connect no se exponen fuera de la red interna.** En Docker Compose no se publican sus puertos, y en kind no tienen Service externo.
* **Fuera de local, el broker exige autenticación y autorización:**
  * **SASL/SCRAM-SHA-512**, con un usuario por componente: un conector de Debezium por servicio y cada microservicio.
  * **ACLs** con lo mínimo: solo el conector de cada servicio escribe en los topics de eventos de ese servicio, y cada microservicio solo lee los topics que consume y escribe en sus DLT. La creación de topics queda fuera de las aplicaciones (`auto.create.topics.enable=false`).
  * **TLS** entre clientes y broker.
* **La API REST de Kafka Connect** solo es accesible desde la red interna, y fuera de local exige autenticación.
* **Las credenciales llegan por variables de entorno**, distintas por componente y por entorno, igual que los secretos de Keycloak (ADR-0022).
* El detalle de usuarios y ACLs está en `docs/strategies/security.md`.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Token del usuario en cada evento** | Vence antes de que se reprocese un evento de la DLQ, identifica al usuario y no a quien publica, y se puede reutilizar mientras está vigente. |
| **Firmar cada evento** (HMAC o firma por servicio) | Protege la integridad aunque alguien llegue al broker, pero exige gestionar claves en Debezium y en todos los consumidores, y no impide leer los datos personales. |
| **SASL/OAUTHBEARER con Keycloak** | Reutiliza el proveedor de identidad, pero suma a Keycloak como dependencia de cada conexión al broker y es más complejo de configurar en Kafka Connect. Se puede adoptar más adelante sin cambiar los eventos. |
| **TLS mutuo como autenticación** | Identifica bien a cada cliente, pero exige emitir y rotar certificados por componente. |
| **Mantener la confianza en la red, sin más** | Deja abierto el fraude descrito en el contexto ante cualquiera con acceso a la red interna. |

## Consecuencias

**Positivas**
* Solo Debezium puede publicar eventos de negocio: un evento falso exige credenciales del conector, no solo acceso a la red.
* Cada componente lee solo lo que necesita, lo que limita quién ve los datos personales.
* Los eventos no cambian: ningún contrato de AsyncAPI se modifica.

**Negativas / costos aceptados**
* Más configuración: usuarios SCRAM, ACLs y certificados por entorno.
* **En local no hay autenticación en el broker**: la protección es solo de red. Un contenedor de la misma red de Docker Compose puede publicar.
* Los consumidores siguen confiando en el contenido del evento. Si las credenciales de un conector se filtran, el riesgo vuelve.
* La herramienta para reprocesar la DLQ, todavía pendiente (ADR-0010), publica en los topics originales. Necesita su propio usuario, con escritura explícita y uso auditado.

**Cómo se verifica**: revisión de `docker-compose.yml` y de los manifiestos de kind (sin puertos ni Services externos de Kafka y Connect). En los entornos con SASL, un test de humo con un usuario sin ACL que intenta publicar en `orders.order.events` y recibe un error de autorización.

## Referencias

* `docs/strategies/security.md`
* `docs/architecture/quality-attributes.md` S3
* ADR-0006, ADR-0010, ADR-0013, ADR-0016, ADR-0022
