# Modelo de Dominio

Un microservicio por sección (ver `docs/README.md` 4.1 y `docs/glosario.md`). Nombres de clases/campos en inglés; descripciones en español.

## Catálogo

Microservicio con BD única (CRUD), sin CQRS.

### Agregados

#### `Product` (raíz de agregado)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `ProductId` | Identificador interno. |
| `sku` | `Sku` (value object) | Clave de negocio única e inmutable una vez creado el producto. |
| `name` | `String` | No vacío. |
| `description` | `String` (opcional) | |
| `categoryId` | `CategoryId` | Referencia a `Category` — por id, no se embebe el objeto completo (son agregados distintos). |
| `unitOfMeasureId` | `UnitOfMeasureId` | Referencia a `UnitOfMeasure` — por id. |
| `minimumStock` | `Quantity` | ≥ 0. Lo consulta Inventario para la alerta de stock mínimo. |
| `active` | `boolean` | Soft delete: nunca se borra físicamente, porque Inventario/Órdenes referencian productos por id en movimientos de kardex y pedidos históricos. |

**Invariantes**: `sku` único e inmutable; `name` no vacío; `minimumStock` ≥ 0.

**Sin precio** (decidido 2026-10-31): el pricing queda fuera de alcance por ahora, coherente con que `vision.md` ya excluye pasarela de pagos/facturación electrónica real. Se puede agregar un campo `price` más adelante si Órdenes lo llega a necesitar.

#### `Category` (raíz de agregado independiente)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `CategoryId` | |
| `name` | `String` | |
| `description` | `String` (opcional) | |
| `parentCategoryId` | `CategoryId` (opcional) | Permite jerarquía (subcategorías) — decidido 2026-10-31. |
| `active` | `boolean` | Soft delete, igual razón que `Product`. |

**Invariante**: no puede haber ciclos en la jerarquía (una categoría no puede ser ancestro de sí misma).

#### `UnitOfMeasure` (raíz de agregado independiente)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `UnitOfMeasureId` | |
| `code` | `String` | Ej. `KG`, `UND`, `BOX`. |
| `name` | `String` | Ej. "Kilogramo", "Unidad", "Caja". |
| `active` | `boolean` | Soft delete. Configurable por el administrador (no es un enum fijo en código) — decidido 2026-10-31. |

### Relaciones entre agregados

`Product` referencia a `Category` y a `UnitOfMeasure` solo por id (son agregados independientes, con su propio ciclo de vida administrado por separado). `Category` se referencia a sí misma vía `parentCategoryId` para la jerarquía.

### Casos de uso (capa `application`)

* **Product**: `RegisterProduct`, `UpdateProduct`, `SetMinimumStock`, `ActivateProduct`, `DeactivateProduct`, `GetProduct`, `GetProductBySku`, `ListProducts`.
* **Category**: `CreateCategory`, `UpdateCategory`, `ActivateCategory`, `DeactivateCategory`, `ListCategories` (como árbol, dado `parentCategoryId`).
* **UnitOfMeasure**: `CreateUnitOfMeasure`, `UpdateUnitOfMeasure`, `ActivateUnitOfMeasure`, `DeactivateUnitOfMeasure`, `ListUnitsOfMeasure`.

### Eventos de dominio

Ninguno por ahora: Inventario y Órdenes consultan Catálogo de forma síncrona (REST + circuit breaker, ver `docs/README.md` 4.1) sin mantener una copia local, así que no hay necesidad de publicar eventos de cambio. Si en el futuro algún servicio necesita cachear datos de producto, se reconsidera agregar `ProductCreated`/`ProductUpdated`/`ProductDeactivated`.

## Inventario

Microservicio con **CQRS completo** (BD escritura + BD lectura + outbox + Debezium, ver `docs/README.md` 3.1). Lo que sigue describe el **lado escritura** (modelo de dominio); el lado lectura se resume en "Modelos de lectura".

### Decisiones de modelado (2026-11-01)

* **Stock por producto (total)**: todas las validaciones de cantidad (reserva, stock mínimo, stock insuficiente) se hacen sobre el total del producto, sin importar la ubicación.
* **Ubicación referencial y opcional**: `locationId` es opcional en los movimientos y no interviene en ninguna validación. Sirve para representar subalmacenes; si más adelante pasa a ser obligatoria, basta con volver requerido el campo, sin rehacer el modelo ni migrar datos.
* **Stock real, reservado y disponible**: se almacenan el stock **real** (físico) y el **reservado**; el **disponible** = real − reservado se calcula. Las reservas se validan contra el disponible.
* **Reserva todo o nada**: si falta stock de algún ítem del pedido, no se reserva nada y el pedido queda `PENDING` en Órdenes (no se puede procesar).
* **El stock real baja al procesar el pedido** (`OrderProcessed`), no al reservar ni al enviar: en ese momento se descuentan el real y el reservado, y se genera la salida en el kardex.
* **El ingreso aumenta el stock al registrar la guía de remisión**; asignar ubicación es un paso aparte que no cambia cantidades (se modela como un traslado, ver `StockTransfer`).

### Agregados

#### `ProductStock` (raíz de agregado)

Saldo de stock de un producto. Es la única fuente de verdad para las validaciones de cantidad.

| Campo | Tipo | Notas |
|---|---|---|
| `productId` | `ProductId` | Identidad del agregado (uno por producto). Referencia a `Product` de Catálogo. |
| `physicalStock` | `Quantity` | Stock **real** (existencia física). ≥ 0. |
| `reservedStock` | `Quantity` | Stock bloqueado por pedidos (suma de las `StockReservation` `ACTIVE` del producto). ≥ 0. |
| `version` | `long` | Bloqueo optimista: evita que dos reservas concurrentes sobre el mismo producto reserven más de lo disponible. |

`availableStock()` = `physicalStock − reservedStock`. Se calcula y no se almacena.

**Invariantes**: `reservedStock` ≥ 0 y `reservedStock` ≤ `physicalStock` (el disponible nunca es negativo).

**Operaciones**:
* `increase(q)`: ingreso por guía de remisión, devolución o reposición por cancelación desde `PROCESSED` → `physicalStock += q`.
* `reserve(q)`: solo si `availableStock()` ≥ `q` → `reservedStock += q`. El real no cambia.
* `release(q)`: `reservedStock -= q` (cancelación de un pedido aún no procesado). El real no cambia.
* `consume(q)`: `physicalStock -= q` y `reservedStock -= q` (al procesar el pedido).

#### `StockMovement` (raíz de agregado, inmutable)

Cada línea del kardex. Solo se agrega (append-only); nunca se modifica ni se elimina. Una corrección se hace con un movimiento nuevo.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `StockMovementId` | |
| `productId` | `ProductId` | |
| `locationId` | `LocationId` (opcional) | Referencial (ver decisiones). |
| `type` | `MovementType` | `INBOUND` (guía de remisión), `OUTBOUND` (pedido procesado), `RETURN` (devolución de pedido entregado), `CANCELLATION` (reposición por cancelar un pedido ya procesado), `TRANSFER_OUT` / `TRANSFER_IN` (traslado). |
| `quantity` | `Quantity` | > 0. El signo lo determina `type`. |
| `documentDate` | `Instant` | Fecha del documento de respaldo. |
| `createdAt` | `Instant` | Fecha en que se registra en el sistema. |
| `source` | `MovementSource` (value object) | Documento que origina el movimiento: `sourceType` (`DELIVERY_NOTE`, `ORDER`, `STOCK_TRANSFER`) + `sourceId`. |
| `unusual` | `boolean` | Se calcula al crear el movimiento: `true` si \|`createdAt` − `documentDate`\| > 48 h (`docs/README.md` 2.2). |

**Invariantes**: `quantity` > 0; inmutable una vez creado.

**Efecto en el stock real**: `INBOUND`/`RETURN`/`CANCELLATION` suman y `OUTBOUND` resta. Las reservas no generan movimientos, porque no cambian el stock real.

**A futuro**: salidas de mercadería por daño o vencimiento (mermas) → nuevo tipo de salida (ej. `WRITE_OFF`, con motivo) que resta del stock real. `MovementType` debe poder ampliarse sin cambiar el resto del modelo. `TRANSFER_OUT` + `TRANSFER_IN` siempre van en pares y **se compensan** (suman cero), así que no cambian el total del producto; solo cambian dónde está registrada la mercadería.

#### `DeliveryNote` — Guía de Remisión (raíz de agregado)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `DeliveryNoteId` | |
| `series` / `number` | `String` | Serie y número de la guía. Únicos en conjunto. |
| `issueDate` | `LocalDate` | Fecha de emisión de la guía. |
| `purchaseDocument` | `PurchaseDocument` (value object) | **Obligatorio**: todo ingreso debe estar respaldado por un documento de compra. |
| `items` | `List<DeliveryNoteItem>` | Al menos uno. Cada ítem tiene `productId` y `quantity` (> 0); no puede repetirse el mismo producto. |
| `registeredAt` | `Instant` | |

**Al registrarla**, en la misma transacción se crea un `StockMovement` `INBOUND` por ítem (sin ubicación, con `documentDate` = `purchaseDocument.issueDate`) y se hace `ProductStock.increase(q)`.

**Invariantes**: `purchaseDocument` obligatorio; al menos un ítem; productos activos en Catálogo (se valida con una consulta síncrona al registrar); inmutable una vez registrada.

##### `PurchaseDocument` (value object)

| Campo | Tipo | Notas |
|---|---|---|
| `documentType` | `PurchaseDocumentType` | `INVOICE` (boleta/factura, ver glosario), `PURCHASE_ORDER`. Ampliable a nuevos tipos. |
| `series` / `number` | `String` | `series` es opcional (una orden de compra puede no tenerla). |
| `issueDate` | `LocalDate` | Es la **fecha de documento** de los movimientos de ingreso (criterio de movimiento inusual). |

No es un agregado: no hay microservicio de Compras, así que la guía solo guarda la referencia al documento que la respalda.

#### `Location` — Ubicación (raíz de agregado)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `LocationId` | |
| `code` | `String` | Único. Ej. `ALM-A`, `ALM-A-E03`. |
| `name` | `String` | |
| `parentLocationId` | `LocationId` (opcional) | Jerarquía opcional (almacén → subalmacén → estante), igual que `Category` en Catálogo. |
| `active` | `boolean` | Soft delete: los movimientos históricos la referencian. |

**Invariantes**: `code` único; sin ciclos en la jerarquía. Todo es **un solo almacén lógico** con subdivisiones internas (multi-almacén sigue fuera de alcance, ver `vision.md`).

#### `StockTransfer` — Traslado (raíz de agregado)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `StockTransferId` | |
| `productId` | `ProductId` | |
| `fromLocationId` | `LocationId` (opcional) | Vacío = mercadería que aún no tiene ubicación. Así, **asignar ubicación** a lo ingresado por una guía es un traslado desde "sin ubicación" y no necesita un flujo propio. |
| `toLocationId` | `LocationId` | Obligatorio. |
| `quantity` | `Quantity` | > 0. |
| `transferDate` | `Instant` | Fecha de documento de los dos movimientos que genera. |

**Al registrarlo** se crean dos `StockMovement` (`TRANSFER_OUT` en origen y `TRANSFER_IN` en destino) con `source` = este traslado. `ProductStock` no cambia.

**Invariantes**: `fromLocationId` ≠ `toLocationId`; ubicaciones activas. Mientras la ubicación sea referencial, **no se valida** que haya suficiente cantidad en el origen, porque el stock por ubicación no es una fuente de verdad. Si la ubicación pasa a ser obligatoria, esta validación se activa.

#### `StockReservation` — Reserva de stock (raíz de agregado)

Detalle de lo bloqueado para un pedido. Permite liberar o consumir exactamente lo reservado y da idempotencia a la saga.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `StockReservationId` | |
| `orderId` | `OrderId` | **Único**: una sola reserva por pedido. Si `OrderRegistered` llega duplicado, no se vuelve a reservar. |
| `items` | `List<ReservationItem>` | `productId` + `quantity`. |
| `status` | `ReservationStatus` | Ver ciclo de vida. |
| `createdAt` / `updatedAt` | `Instant` | |

**Ciclo de vida**:

```
PENDING  → ACTIVE      (llegó stock suficiente para todos los ítems)
PENDING  → RELEASED    (pedido cancelado antes de tener stock; no hay nada que liberar)
ACTIVE   → RELEASED    (OrderCancelled sin procesar → ProductStock.release por ítem)
ACTIVE   → CONSUMED    (OrderProcessed → ProductStock.consume + StockMovement OUTBOUND por ítem)
```

Correspondencia con `OrderStatus` en Órdenes: reserva `PENDING` ↔ pedido `PENDING`; `ACTIVE` ↔ `RESERVED`; `CONSUMED` ↔ `PROCESSED` en adelante.

* Al consumir `OrderRegistered`: si **todos** los ítems tienen `availableStock()` suficiente, la reserva se crea en `ACTIVE`, se hace `reserve` en cada `ProductStock` y se publica `StockReserved`. Si falta alguno, se crea en `PENDING` sin bloquear nada, se genera la alerta de stock insuficiente y se publica `StockInsufficient` indicando qué ítems faltan (todo o nada).
* **Reintento de `PENDING`**: cuando un ingreso (`DeliveryNote`, devolución o reposición por cancelación) aumenta el stock de un producto, se reintentan las reservas `PENDING` que lo incluyen, en orden de llegada (FIFO). Si ahora alcanza para todos sus ítems, la reserva pasa a `ACTIVE` y se publica `StockReserved`, y Órdenes pasa el pedido de `PENDING` a `RESERVED`.
* **Cancelación de un pedido ya procesado** (`OrderCancelled` con el pedido en `PROCESSED`): la reserva ya está `CONSUMED`, así que no se libera nada. Se repone el stock real con un `StockMovement` `CANCELLATION` por ítem + `ProductStock.increase`.

#### `Alert` — Alerta (raíz de agregado)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `AlertId` | |
| `type` | `AlertType` | `MINIMUM_STOCK`, `UNUSUAL_MOVEMENT`, `INSUFFICIENT_STOCK`, `SYNC_FAILURE`. |
| `reference` | `String` | Qué la originó: `productId`, `stockMovementId` u `orderId`, según el tipo. |
| `message` | `String` | |
| `status` | `AlertStatus` | `ACTIVE` → `ACKNOWLEDGED` (el administrador la vio) → `RESOLVED`. |
| `createdAt` | `Instant` | |

Se exponen por el endpoint de "alertas activas" de Inventario (`docs/README.md` 4.3).

* `MINIMUM_STOCK`: se genera cuando, tras una operación, el stock real (`physicalStock`) queda por debajo del `minimumStock` del producto (consultado a Catálogo). No se duplica mientras ya exista una alerta `ACTIVE` para ese producto, y se resuelve sola cuando el stock vuelve a superar el mínimo.
* `UNUSUAL_MOVEMENT`: una por cada `StockMovement` con `unusual = true`.
* `INSUFFICIENT_STOCK`: una por cada reserva que queda en `PENDING`.
* `SYNC_FAILURE`: fallos de sincronización CQRS (`docs/README.md` 3.1).

### Relaciones entre agregados

Todos se referencian solo por id. `ProductStock`, `StockMovement`, `DeliveryNote`, `StockTransfer` y `StockReservation` referencian `Product` (Catálogo) por `productId`. `StockMovement` y `StockTransfer` referencian `Location` por id. `StockMovement.source` apunta al agregado que lo originó.

Varios agregados cambian en una misma transacción (ej. `DeliveryNote` + `StockMovement` + `ProductStock`). Se acepta por pragmatismo: comparten la BD de escritura y la consistencia inmediata del stock es un requisito de negocio. `ProductStock` usa bloqueo optimista para resolver la concurrencia.

### Casos de uso (capa `application`)

* **Ingresos**: `RegisterDeliveryNote`, `GetDeliveryNote`, `ListDeliveryNotes`.
* **Ubicaciones**: `CreateLocation`, `UpdateLocation`, `ActivateLocation`, `DeactivateLocation`, `ListLocations` (como árbol).
* **Traslados**: `TransferStock` (también cubre "asignar ubicación", con `fromLocationId` vacío).
* **Reservas (disparados por eventos de Órdenes)**: `ReserveStockForOrder` (← `OrderRegistered`), `ConsumeReservation` (← `OrderProcessed`), `HandleOrderCancellation` (← `OrderCancelled`: libera la reserva si el pedido no estaba procesado, o repone el stock real con un `CANCELLATION` si ya lo estaba), `RestockReturnedOrder` (← `OrderReturned`: `StockMovement` `RETURN` + `ProductStock.increase`), `RetryPendingReservations` (interno, tras cada ingreso).
* **Alertas**: `AcknowledgeAlert`, `ResolveAlert`, `ListActiveAlerts`.
* **Consultas (lado lectura)**: `GetProductStock`, `GetKardex` (por producto y rango de fechas, con filtro opcional por ubicación).

### Eventos

**Consumidos (desde Órdenes)**: `OrderRegistered`, `OrderProcessed`, `OrderCancelled` (incluye el estado previo del pedido, para saber si ya estaba procesado), `OrderReturned`.

**Publicados a Órdenes (saga)**: `StockReserved`, `StockInsufficient`.

**Publicados para el lado lectura (CQRS, vía outbox + Debezium)**: `StockMovementRecorded`, `ProductStockChanged`, `DeliveryNoteRegistered`, `StockTransferred`, `AlertRaised`, `AlertStatusChanged`, `LocationChanged`.

### Modelos de lectura (BD de lectura)

* **`KardexEntry`**: una fila por `StockMovement`, con su **saldo acumulado** por producto (y por ubicación cuando la hay). Es la base de los reportes de kardex.
* **`ProductStockView`**: stock real, reservado y disponible por producto, con el desglose referencial por ubicación.
* **`ActiveAlertView`**: alertas `ACTIVE`/`ACKNOWLEDGED` para el panel del administrador.

## Órdenes

Microservicio con **BD única + tabla outbox** (publica sus eventos vía Debezium, igual que Inventario), **sin CQRS** — decidido 2026-11-01. Controla el ciclo de vida del pedido (`docs/README.md` 2.1), el scheduler de expiración y el registro de incidencias.

### Decisiones de modelado (2026-11-01)

* **El pedido guarda la información del cliente tal como era al crearlo**: contacto (para notificaciones) y dirección de entrega.
* **Snapshot del producto en el ítem, en la BD de escritura** (`sku`, nombre, unidad de medida), obtenido de Catálogo al registrar: el ítem queda trazado tal como fue pedido aunque el producto cambie o se desactive después.
* **El pedido no se modifica**: solo avanza, se cancela o se devuelve. Para cambiar ítems se cancela y se crea otro.
* **Transiciones manuales por el administrador** (procesar, enviar, entregar); al enviar solo se registra la fecha (sin transportista ni tracking por ahora).
* **Devolución solo total** por ahora, sin plazo; se modela con lista de ítems devueltos para poder habilitar devoluciones parciales a futuro (ej. pedido parcialmente dañado) sin rehacer el modelo.
* **Expiración configurable**: el plazo de 48 h es una propiedad (`orders.expiration.timeout=48h`), no está fijo en código.

### Agregados

#### `Order` — Pedido (raíz de agregado)

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `OrderId` | |
| `customerId` | `CustomerId` | Id del usuario en Keycloak (`sub` del token). |
| `contact` | `ContactInfo` (value object) | Snapshot al registrar. |
| `shippingAddress` | `Address` (value object) | Snapshot al registrar. |
| `items` | `List<OrderItem>` | Al menos uno; sin productos repetidos. |
| `status` | `OrderStatus` | `REGISTERED`, `PENDING`, `RESERVED`, `PROCESSED`, `SHIPPED`, `DELIVERED`, `CANCELLED`, `RETURNED`. |
| `statusHistory` | `List<StatusChange>` | Auditoría de **todas** las transiciones (ver abajo). |
| `registeredAt` | `Instant` | |
| `expiresAt` | `Instant` | `registeredAt` + plazo configurado, calculado al registrar (un cambio posterior de la propiedad no afecta pedidos ya creados). |
| `processedAt` / `shippedAt` / `deliveredAt` | `Instant` (opcionales) | |
| `cancellation` | `Cancellation` (value object, opcional) | Solo si fue cancelado. |
| `orderReturn` | `OrderReturn` (value object, opcional) | Solo si fue devuelto. |
| `version` | `long` | Bloqueo optimista (ej. el scheduler y un `StockReserved` llegando a la vez). |

**Invariantes**:
* Al menos un ítem; `quantity` > 0; sin `productId` repetido.
* Solo las transiciones de `docs/README.md` 2.1; cualquier otra se rechaza.
* Solo se procesa desde `RESERVED`.
* Inmutable en sus datos (cliente, dirección, ítems) una vez registrado.

**Operaciones**:
* `register(...)`: crea en `REGISTERED`; los productos deben estar activos en Catálogo (consulta síncrona, que también provee el snapshot).
* `markReserved()` (← `StockReserved`): `REGISTERED`/`PENDING` → `RESERVED`.
* `markPending()` (← `StockInsufficient`): `REGISTERED` → `PENDING`.
* `process()`, `ship()`, `deliver()`: administrador.
* `cancel(reason, actor)`: ver reglas de cancelación.
* `returnOrder(reason, items)`: solo desde `DELIVERED`; hoy `items` debe incluir **todos** los ítems con su cantidad completa.

**Reglas de cancelación**:

| Actor | Estados desde los que puede cancelar |
|---|---|
| Cliente (solo sus pedidos) | `REGISTERED`, `PENDING`, `RESERVED` |
| Administrador | `REGISTERED`, `PENDING`, `RESERVED`, `PROCESSED` |
| Sistema (expiración) | `REGISTERED`, `PENDING`, `RESERVED` cuando `now` ≥ `expiresAt` |

El motivo es **obligatorio** siempre (en la expiración lo pone el sistema, ej. "Expirado sin procesar").

**Idempotencia frente a eventos de Inventario**: un `StockReserved`/`StockInsufficient` que llega cuando el pedido ya no está en un estado compatible (ej. ya `CANCELLED`, o ya `RESERVED`) se ignora. Si el pedido ya fue cancelado, Inventario libera la reserva por su cuenta al consumir `OrderCancelled`.

##### `OrderItem` (entidad dentro de `Order`)

| Campo | Tipo | Notas |
|---|---|---|
| `productId` | `ProductId` | Referencia a Catálogo. |
| `sku` | `Sku` | Snapshot. |
| `productName` | `String` | Snapshot. |
| `unitOfMeasureCode` | `String` | Snapshot (ej. `UND`, `KG`). |
| `quantity` | `Quantity` | > 0. |

##### Value objects

* **`ContactInfo`**: `fullName`, `email` (opcional), `phone` (opcional). Al menos uno de `email`/`phone` es obligatorio (Notificaciones envía email o SMS).
* **`Address`**: `line` (dirección), `district`, `city`, `region`, `reference` (opcional).
* **`StatusChange`**: `from`, `to`, `changedAt`, `actor` (`Actor`), `reason` (opcional).
* **`Actor`**: `type` (`CUSTOMER`, `ADMIN`, `SYSTEM`) + `userId` (opcional, vacío para `SYSTEM`).
* **`Cancellation`**: `reason`, `actor`, `previousStatus`, `cancelledAt`.
* **`OrderReturn`**: `reason`, `items` (`productId` + `quantity`), `returnedAt`. Hoy siempre contiene todos los ítems; mantener la lista permite devoluciones parciales a futuro.

#### `Incident` — Registro de incidencias (raíz de agregado)

Registro de negocio de cancelaciones y devoluciones con su motivo (`docs/README.md` 2 y 4.3). Es independiente del `statusHistory` del pedido, que es auditoría de todas las transiciones; `Incident` es el registro que se consulta y reporta como tal.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `IncidentId` | |
| `orderId` | `OrderId` | |
| `type` | `IncidentType` | `CANCELLATION`, `RETURN`. |
| `reason` | `String` | Obligatorio. |
| `actor` | `Actor` | Quién la originó. |
| `previousStatus` | `OrderStatus` | Estado del pedido antes de la incidencia. |
| `occurredAt` | `Instant` | |

Se crea en la misma transacción que la cancelación/devolución del pedido. Inmutable.

#### `Alert` — Alerta (raíz de agregado)

Misma estructura y ciclo (`ACTIVE` → `ACKNOWLEDGED` → `RESOLVED`) que en Inventario; se expone por el endpoint de "alertas activas" de Órdenes (`docs/README.md` 4.3).

* `ORDER_CANCELLED`: solo para cancelaciones **automáticas** por expiración y para las del **administrador desde `PROCESSED`** (ambas indican un problema operativo). Las cancelaciones del cliente no generan alerta.

### Scheduler de expiración

`ExpireOrders` corre periódicamente y cancela (actor `SYSTEM`) los pedidos en `REGISTERED`, `PENDING` o `RESERVED` con `expiresAt` vencido. Con varias instancias del servicio, se ejecuta en una sola mediante **ShedLock**. Usa bloqueo optimista para no pisar una transición concurrente (ej. el administrador procesando el pedido en ese momento).

### Relaciones entre agregados

`Order` referencia productos (Catálogo) por `productId` + snapshot. `Incident` y `Alert` referencian `Order` por `orderId`. `Order` + `Incident` (+ `Alert`, si corresponde) se guardan en una misma transacción junto con el evento en el outbox.

### Casos de uso (capa `application`)

* **Cliente**: `RegisterOrder`, `CancelOrder` (propio, antes de procesar), `GetOrder` (propio), `ListMyOrders`.
* **Administrador**: `ProcessOrder`, `ShipOrder`, `DeliverOrder`, `CancelOrder` (incluye `PROCESSED`), `ReturnOrder`, `ListOrders` (filtros por estado/fechas), `ListIncidents`, `AcknowledgeAlert`, `ResolveAlert`, `ListActiveAlerts`.
* **Disparados por eventos de Inventario**: `MarkOrderReserved` (← `StockReserved`), `MarkOrderPending` (← `StockInsufficient`).
* **Interno**: `ExpireOrders` (scheduler).

### Eventos

**Publicados (vía outbox)** — todos llevan `orderId`, `customerId` y `contact`, para que Notificaciones no necesite consultar a Órdenes:

| Evento | Datos adicionales | Consumidores |
|---|---|---|
| `OrderRegistered` | `items` (`productId`, `sku`, `productName`, `quantity`) | Inventario, Notificaciones |
| `OrderPending` | ítems faltantes (de `StockInsufficient`) | Notificaciones |
| `OrderReserved` | `previousStatus` (`REGISTERED` o `PENDING`) | Notificaciones (solo avisa si venía de `PENDING`) |
| `OrderProcessed` | `items` | Inventario |
| `OrderShipped` | `shippedAt` | Notificaciones |
| `OrderDelivered` | `deliveredAt` | Notificaciones |
| `OrderCancelled` | `previousStatus`, `reason`, `actor`, `items` | Inventario (libera reserva o repone según `previousStatus`), Notificaciones |
| `OrderReturned` | `items` devueltos, `reason` | Inventario, Notificaciones |

**Consumidos (desde Inventario)**: `StockReserved`, `StockInsufficient`.

## Notificaciones

Microservicio **consumidor puro**: escucha los eventos de pedido de Órdenes vía Kafka y avisa al **cliente** por email y/o SMS. No expone comandos de negocio ni publica eventos. **BD pequeña** solo para el registro de notificaciones (idempotencia + auditoría), sin CQRS.

### Decisiones de modelado (2026-11-01)

* **Solo se notifica al cliente**; el administrador usa el panel de alertas (`docs/README.md` 4.3).
* **Todos los canales disponibles**: si el contacto tiene email y teléfono, se envía por ambos. La preferencia de canal queda para más adelante.
* **No consulta a Órdenes**: el contacto y los datos necesarios viajan en cada evento (ver eventos de Órdenes).
* **Proveedores detrás de un puerto** (hexagonal): hoy SMTP contra **Mailpit** (Docker Compose) para email y un adaptador que solo escribe en el log para SMS. Proveedores reales (SendGrid, Twilio, AWS SES/SNS…) se agregan como nuevos adaptadores sin tocar el dominio.
* **Plantillas en el repo, en español**: Thymeleaf para email, texto plano para SMS. Edición por el administrador queda fuera de alcance.
* **Reintentos acotados** según la política de `docs/README.md` 5.1: nunca infinitos.

### Qué evento genera qué aviso

| Evento | ¿Notifica? | Plantilla (`NotificationTemplate`) |
|---|---|---|
| `OrderRegistered` | Sí | `ORDER_REGISTERED` — confirmación del pedido con sus ítems. |
| `OrderPending` | Sí | `ORDER_PENDING` — en espera por falta de stock. |
| `OrderReserved` | Solo si `previousStatus` = `PENDING` | `ORDER_STOCK_AVAILABLE` — ya hay stock para tu pedido. |
| `OrderProcessed` | No | — (no cambia nada para el cliente). |
| `OrderShipped` | Sí | `ORDER_SHIPPED` |
| `OrderDelivered` | Sí | `ORDER_DELIVERED` |
| `OrderCancelled` | Sí | `ORDER_CANCELLED` — incluye el motivo. |
| `OrderReturned` | Sí | `ORDER_RETURNED` |

### Agregados

#### `Notification` (raíz de agregado)

Un registro por cada aviso enviado (o intentado) por **un canal**: un evento con email y teléfono genera dos `Notification`.

| Campo | Tipo | Notas |
|---|---|---|
| `id` | `NotificationId` | |
| `eventId` | `EventId` | Id único del evento de Kafka que la originó. |
| `orderId` | `OrderId` | |
| `channel` | `NotificationChannel` | `EMAIL`, `SMS`. |
| `recipient` | `String` | Email o teléfono, copiado del `contact` del evento. |
| `template` | `NotificationTemplate` | Ver tabla anterior. |
| `status` | `NotificationStatus` | `PENDING` → `SENT` / `FAILED`. |
| `attempts` | `int` | Intentos realizados contra el proveedor (máximo según 5.1). |
| `lastError` | `String` (opcional) | Último error del proveedor. |
| `createdAt` / `sentAt` | `Instant` | `sentAt` solo si `SENT`. |

**Invariantes**:
* `(eventId, channel)` **único**: si Kafka entrega el mismo evento dos veces, no se crea ni se envía otra notificación por ese canal (idempotencia).
* `SENT` y `FAILED` son estados finales; `attempts` nunca supera el máximo configurado.

**Flujo**: al consumir un evento → se decide si notifica (tabla anterior) → por cada canal disponible en `contact`, se crea la `Notification` en `PENDING` (si no existía para ese `eventId` + canal) → se renderiza la plantilla → se envía por el puerto `NotificationSender` (Resilience4j: timeout + retry + circuit breaker por proveedor) → `SENT`, o `FAILED` al agotar los reintentos, publicando el evento original a la DLQ para reprocesamiento manual. El consumidor de Kafka no reintenta además por su cuenta (5.1, "no multiplicar reintentos").

### Puertos

* **Entrada**: consumidor de eventos de pedido (adaptador Kafka).
* **Salida**: `NotificationSender` (un adaptador por canal/proveedor: `SmtpEmailSender` → Mailpit, `LoggingSmsSender`), `TemplateRenderer` (Thymeleaf), `NotificationRepository`.

### Casos de uso (capa `application`)

* `HandleOrderEvent` (disparado por cada evento de pedido; decide plantilla y canales).
* `SendNotification` (envía una `Notification` y actualiza su estado).
* Administrador (consulta/auditoría): `ListNotifications` (por pedido, estado o fechas), `ReprocessFailedNotification` (reenvío manual de una `FAILED`, que también tiene máximo de intentos).

### Eventos

**Consumidos (desde Órdenes)**: `OrderRegistered`, `OrderPending`, `OrderReserved`, `OrderShipped`, `OrderDelivered`, `OrderCancelled`, `OrderReturned`. (`OrderProcessed` no se consume.)

**Publicados**: ninguno.
