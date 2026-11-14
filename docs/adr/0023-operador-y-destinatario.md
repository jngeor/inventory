# ADR-0023: Rol de operador y destinatario separado del usuario

* **Estado**: Aceptado
* **Fecha**: 2026-11-07
* **Ticket**: KOAL-9
* **Amplía**: ADR-0013, en sus roles y en el origen del `customerId`.

## Contexto

El diseño suponía un e-commerce: un cliente con cuenta registra sus propios pedidos, así que `customerId` era siempre el `sub` del token. Pero el sistema no es necesariamente un e-commerce: también puede administrar un dark store. Ahí, quien opera no es quien recibe el pedido, y el destinatario puede no tener cuenta.

Por ahora los pedidos llegan desde un frontend, registrados por un cliente o por un operador. A futuro llegarán desde otros sistemas.

## Decisión

* **El usuario y el destinatario son conceptos distintos.** El usuario es quien actúa en el sistema, y queda registrado como `Actor`. El destinatario es quien recibe el pedido y sus avisos, y queda en `contact` y `shippingAddress`.
* **Se agrega el rol `OPERATOR`**, para el personal que opera día a día. `CUSTOMER`, `ADMIN` y `SERVICE` se mantienen.
* **`customerId` pasa a ser opcional.** Se guarda, desde el `sub`, solo si registra un `CUSTOMER`. Un pedido registrado por un operador o un administrador no lo tiene, y `registeredBy` indica quién lo registró.
* **Notificaciones avisa siempre al destinatario**, tenga o no cuenta.
* **La regla de pedido ajeno aplica solo al rol `CUSTOMER`**: ve solo los pedidos con su `customerId`, y los demás responden 404. Un operador ve todos.
* **El ajuste de stock sigue siendo solo de `ADMIN`.** El ajuste es la vía con la que se podría encubrir un robo, y el operador es quien maneja la mercadería.

| Operación | `CUSTOMER` | `OPERATOR` | `ADMIN` |
|---|---|---|---|
| Consultar productos y categorías | Sí | Sí | Sí |
| Consultar stock, kardex y reporte | No | Sí | Sí |
| Registrar guías y trasladar stock | No | Sí | Sí |
| Registrar pedidos | Sí | Sí | Sí |
| Procesar, enviar y entregar pedidos | No | Sí | Sí |
| Cancelar antes de procesar | Solo los suyos | Sí | Sí |
| Cancelar desde `PROCESSED` y devolver | No | No | Sí |
| Marcar alertas como vistas | No | Sí | Sí |
| Consultar notificaciones | No | Sí | Sí |
| Reenviar notificaciones fallidas | No | No | Sí |
| Resolver alertas y reconstruir proyecciones | No | No | Sí |
| Ajustar stock | No | No | Sí |
| Modificar catálogo y ubicaciones | No | No | Sí |

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Mantener solo cliente y administrador** | Obligaría a dar permisos de administrador a quien opera, incluido el ajuste de stock. |
| **El operador indica el `customerId` del destinatario** | Exige que todo destinatario tenga cuenta y buscar usuarios en Keycloak. Se puede agregar después como campo opcional. |
| **Maestro de clientes** | Es un contexto nuevo. Hoy no hay necesidad de historial por comprador ni de datos fiscales. |
| **Sin rol `CUSTOMER`** | El frontend también puede ser usado por clientes. |

## Consecuencias

**Positivas**
* Un destinatario sin cuenta recibe avisos igual.
* El operador trabaja sin tener los permisos que protegen contra el fraude.
* Agregar un canal externo no cambia el modelo: sería un nuevo cliente de Keycloak con token de servicio (ADR-0022), que registra pedidos con su propio `Actor`.

**Negativas / costos aceptados**
* Un pedido registrado por un operador no aparece en la lista de ningún cliente, aunque el destinatario tenga cuenta.
* `customerId` puede faltar en los eventos, y ningún consumidor puede depender de él.
* La idempotencia ya no se puede basar en `customerId`: se basa en el usuario que registra.
* Hay un rol más que probar en cada operación.
* El registro de pedidos desde otros sistemas queda por definir: cómo se identifican y si un pedido externo necesita su propia referencia.

**Cómo se verifica**: escenario S2 de `quality-attributes.md`, con tokens de cliente, operador y administrador.

## Referencias

* `docs/domain-model.md`, Órdenes
* `docs/vision.md` 4
* `docs/api/README.md`
* ADR-0013, ADR-0022
