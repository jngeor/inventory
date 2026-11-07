# ADR-0009: Ante un fallo de proyección, dejar pasar y marcar

* **Estado**: Aceptado
* **Fecha**: 2026-11-01 (escalamiento definido el 2026-11-07)
* **Ticket**: KOAL-4

## Contexto

El proyector aplica los eventos de stock en orden por producto (ADR-0008). Si uno falla tras agotar los reintentos (ADR-0010), va a la DLQ y deja un hueco: el saldo de los eventos siguientes de ese producto puede quedar mal.

Hay que elegir entre dos riesgos: detener la proyección, con datos congelados, o seguir, con un saldo que puede estar mal. La escritura no se ve afectada en ningún caso, porque PostgreSQL es la fuente de verdad.

## Decisión

* **La proyección no se detiene.** Los eventos siguientes, de ese producto y de los demás, se siguen aplicando: detenerla puede causar un problema mayor.
* **El producto queda marcado `outOfSync`** en `ProductStockView` y en su kardex, y la API de consultas lo informa en la respuesta, para que nadie confíe en ese saldo.
* **Se genera la alerta `SYNC_FAILURE`** con el `productId` y la referencia al evento en la DLQ.
* **Una persona monitorea estas alertas y cada una se resuelve en 24 horas como máximo.** El plazo es en horas corridas, sin horario laboral.
* **A las 20 horas (configurable), si sigue sin resolver, Grafana envía una alerta de escalamiento por correo** al responsable, hoy la misma persona que monitorea.
  * **Inventario publica en Prometheus la antigüedad, en segundos, de la `SYNC_FAILURE` sin resolver más antigua**, y vale 0 si no hay ninguna. La lee de la BD de escritura, porque `ActiveAlertView` depende de la proyección que puede estar fallando.
  * **`ACTIVE` y `ACKNOWLEDGED` cuentan como sin resolver**: el reloj solo se detiene en `RESOLVED`.
  * **La regla usa `max()`**, porque cada instancia reporta el mismo valor. El umbral vive en la regla, versionada en el repo, sin tocar el código de Inventario.
* **Resolver** es corregir la causa, reprocesar el evento desde la DLQ y ejecutar `RebuildProductProjection(productId)`, que recalcula el kardex y el saldo desde la BD de escritura y quita la marca. Es una operación administrativa, idempotente y por producto.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Detener la partición hasta resolver el fallo** | Conserva el orden, pero congela también a los demás productos de esa partición, por un problema de uno solo. |
| **Detener solo el producto afectado** (retener sus eventos) | Hay que guardar los eventos retenidos y volver a aplicarlos en orden. Lo mismo se logra reconstruyendo desde la escritura. |
| **Reintentar sin límite** | Bloquea la partición igual que detenerla, y va contra la regla de ADR-0010. |
| **Reconstruir automáticamente al fallar** | Si la causa sigue presente, falla otra vez y se vuelve un ciclo de reintentos. Además, una persona debe conocer la causa. |
| **Ignorar el fallo sin marcar** | Mostraría un saldo incorrecto como si fuera confiable, en un sistema cuyo kardex sirve para detectar manipulaciones. |
| **Grafana consulta la BD de Inventario para escalar** | Rompe ADR-0003: solo el dueño accede a su BD. |
| **Alertar si hay alertas activas durante 20 h seguidas** | Si una se resuelve justo cuando aparece otra, el conteo nunca baja y se suman tiempos de alertas distintas. |
| **Inventario envía el correo con un job propio** | Agrega envío de correos a Inventario, y Notificaciones solo atiende a clientes. |

## Consecuencias

**Positivas**
* Un evento dañado solo afecta a un producto, y esa afectación es visible.
* La recuperación es por producto y no toca a los demás.

**Negativas / costos aceptados**
* Mientras dure `outOfSync`, hasta 24 horas, el saldo proyectado de ese producto puede estar mal. Esto no afecta las reservas, que se validan contra la escritura.
* La política depende de una persona. Hoy el monitoreo y el escalamiento recaen en la misma, así que no hay un segundo responsable si no está disponible.
* Si el servicio Inventario está caído, la métrica deja de actualizarse y el escalamiento no se dispara. Ese caso debe cubrirlo la alerta operativa de servicio caído.

**Cómo se verifica**: escenarios D4 y O2 de `quality-attributes.md`.

## Referencias

* `docs/README.md` 3.1, 5.1
* `docs/domain-model.md`, Inventario (`Alert`, "Modelos de lectura")
* ADR-0004, ADR-0008, ADR-0010
