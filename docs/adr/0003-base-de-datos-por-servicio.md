# ADR-0003: Cada microservicio es dueño exclusivo de su base de datos

* **Estado**: Aceptado
* **Fecha**: 2026-10-31
* **Ticket**: KOAL-1 (documentado en KOAL-4)

## Contexto

Con cuatro microservicios (ADR-0001), una BD compartida volvería a acoplarlos: un cambio de esquema rompería a otros servicios, se podría saltar la API de otro contexto con un `JOIN`, y no habría límites de transacción claros.

Además, los contextos necesitan cosas distintas:

* Inventario necesita una BD de lectura para reportes (ADR-0004).
* Órdenes necesita un outbox y un lock para el scheduler.
* Notificaciones solo necesita un registro de envíos.

## Decisión

* **Cada microservicio tiene su propia BD**, y es el único que la lee y la escribe, también para reportes (context-map, regla 1).
* **Las referencias entre contextos son solo por id** (`productId`, `orderId`, `customerId`). Si se necesita un dato de otro contexto, se pide por su API (Catálogo) o viaja en el evento (ej. `contact` en los eventos de pedido). Órdenes guarda un **snapshot** del producto en `OrderItem` (ACL, context-map R2).
* **Tecnología**: PostgreSQL para todas las BD transaccionales (Catálogo, Inventario escritura, Órdenes, Notificaciones). MongoDB para la BD de lectura de Inventario (`docs/README.md` 3.1). Las BD con outbox (Inventario escritura, Órdenes) tienen replicación lógica habilitada para Debezium.
* **Una base y un usuario por servicio en todos los entornos**, y cada usuario solo tiene permisos sobre su propia base. Lo que cambia entre entornos es la instancia:

| Entorno | Instancia de PostgreSQL | Keycloak |
|---|---|---|
| Desarrollo (Docker Compose / kind) | Una compartida, con `wal_level=logical` para toda la instancia | Quinta base en la instancia compartida, con su propio usuario |
| Certificación | Una por servicio, con la misma topología que producción y menor tamaño | BD propia |
| Producción | Una por servicio, con alta disponibilidad y backups | BD propia, aislada |

* En certificación y producción, `wal_level=logical` se activa solo en las instancias de Inventario escritura y Órdenes.
* **Debezium**: un conector por base con outbox (Inventario escritura y Órdenes), cada uno con su slot de replicación y un usuario con permiso de replicación.
* **El proveedor de nube queda sin definir** hasta que exista esa necesidad.
* **Reglas para que el cambio de entorno sea solo de configuración**:
  * Cada servicio recibe su propia URL, usuario y contraseña por variables de entorno, sin credenciales compartidas.
  * Cada servicio tiene sus propias migraciones, sin depender de nada a nivel de instancia.
  * CI construye la imagen una vez y esa misma imagen se promueve entre entornos; solo cambian los valores de Helm o Kustomize.
  * Los conectores de Debezium están parametrizados: host, base y credenciales no van fijos.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **BD compartida con esquemas por servicio** y acceso cruzado permitido | Reintroduce el acoplamiento: los reportes cruzados por `JOIN` hacen que nadie pueda cambiar su esquema sin coordinar. |
| **BD compartida solo para lectura** (ej. un esquema de reportes común) | Crea un modelo canónico que todos deben mantener. Los reportes que se necesitan hoy (kardex) son de un solo contexto y se resuelven dentro de Inventario. |
| **Caché local de productos** en Inventario y Órdenes | Requiere eventos de producto y consistencia eventual del catálogo. Hoy basta con la consulta síncrona; si cambia, Catálogo publicaría `ProductCreated`/`ProductUpdated`/`ProductDeactivated` (`domain-model.md`, Catálogo). |

## Consecuencias

**Positivas**
* Cada servicio evoluciona su esquema solo, con sus propias migraciones.
* La transacción de cada caso de uso queda dentro de un servicio: el agregado y el outbox se guardan juntos (ADR-0005).
* Cada BD puede ser de la tecnología que mejor le sirva (PostgreSQL + MongoDB en Inventario).

**Negativas / costos aceptados**
* No hay transacciones ni consultas entre contextos. La consistencia entre Órdenes e Inventario es eventual (ADR-0005).
* Algunos datos se duplican a propósito (snapshot del producto, contacto del cliente) y pueden quedar desactualizados respecto de su origen. Se acepta, porque el pedido debe reflejar lo que se pidió.
* Un reporte que cruce contextos (ej. pedidos con su stock) requerirá componer APIs o un modelo de lectura nuevo.
* En desarrollo los fallos no quedan aislados: si cae la instancia compartida, caen todas las bases y tampoco se pueden emitir tokens nuevos. Además, un conector detenido mucho tiempo retiene WAL en su slot y puede llenar el disco compartido.
* Mover datos a otra instancia exige cuidado con Debezium: los slots de replicación no viajan con `pg_dump`, así que primero hay que vaciar el outbox y luego recrear el slot en la instancia nueva.
* Las metas de `quality-attributes.md` se miden sobre Docker Compose y deben volver a medirse en certificación.

**Cómo se verifica**: un usuario de BD por servicio, con permisos solo sobre su base (configuración de Docker Compose / Helm); ninguna configuración de servicio apunta a la BD de otro; revisión de las migraciones.

## Referencias

* `docs/architecture/context-map.md`, reglas 1 y 2
* `docs/architecture/c4-model.md`, nivel 2
* `docs/README.md` 3.1
