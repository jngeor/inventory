# Glosario (lenguaje ubicuo: español ↔ código en inglés)

Convención: la documentación de negocio (README, vision.md) se escribe en **español**; el código (clases, propiedades, métodos, eventos, nombres de microservicio) se escribe en **inglés**, en camelCase para propiedades/métodos y PascalCase para clases. Esta tabla es la referencia para mantener esos nombres consistentes entre microservicios.

## Microservicios

| Español (docs) | Código (nombre de servicio / paquete) |
|---|---|
| Catálogo | `catalog` |
| Inventario | `inventory` |
| Órdenes | `orders` |
| Notificaciones | `notifications` |

## Entidades / Value Objects

| Español | Clase |
|---|---|
| Producto | `Product` |
| Ubicación | `Location` |
| Pedido | `Order` |
| Ítem de Pedido | `OrderItem` |
| Datos de contacto del cliente | `ContactInfo` |
| Dirección de entrega | `Address` (campo `shippingAddress`) |
| Cancelación (datos) | `Cancellation` |
| Devolución (datos) | `OrderReturn` |
| Quién realiza una acción (cliente / administrador / sistema) | `Actor` |
| Kardex / Movimiento (entrada o salida) | `StockMovement` |
| Alerta | `Alert` |
| Incidencia | `Incident` |
| Guía de Remisión | `DeliveryNote`  |
| Documento de Compra (genérico) | `PurchaseDocument` |
| Boleta / Factura | Ambas se modelan como la misma clase **`Invoice`** (en facturación electrónica son el mismo documento, solo difieren en una propiedad de tipo, ej. `documentType`)  |
| Orden de Compra | `PurchaseOrder` |
| Stock real (físico) | propiedad `physicalStock` |
| Stock bloqueado / reservado | propiedad `reservedStock`  |
| Stock disponible (real − reservado) | `availableStock()` — calculado, no se almacena |
| Saldo de stock de un producto | `ProductStock` |
| Reserva de stock de un pedido | `StockReservation` |
| Traslado entre ubicaciones | `StockTransfer` |
| Ajuste de stock (corrección de un error o de un conteo físico) | `StockAdjustment` |
| Tipo de movimiento de kardex | `MovementType` (`INBOUND`, `OUTBOUND`, `RETURN`, `CANCELLATION`, `TRANSFER_OUT`, `TRANSFER_IN`, `ADJUSTMENT_IN`, `ADJUSTMENT_OUT`) |

## Estados del pedido (`OrderStatus`)

| Español (`docs/README.md` 2.1) | Código |
|---|---|
| `REGISTRADO` | `REGISTERED` |
| `PENDIENTE` | `PENDING` |
| `RESERVADO` | `RESERVED` |
| `PROCESADO` | `PROCESSED` |
| `ENVIADO` | `SHIPPED` |
| `ENTREGADO` | `DELIVERED` |
| `DEVUELTO` | `RETURNED` |
| `CANCELADO` | `CANCELLED` |

## Eventos de dominio

| Español (`docs/README.md` 4.2) | Código (clase de evento / topic Kafka) |
|---|---|
| `PedidoRegistrado` | `OrderRegistered` |
| `StockReservado` | `StockReserved` |
| `StockInsuficiente` | `StockInsufficient` |
| `PedidoPendiente` | `OrderPending` |
| `PedidoReservado` | `OrderReserved` |
| `PedidoCancelado` | `OrderCancelled` |
| `PedidoProcesado` | `OrderProcessed` |
| `PedidoEnviado` | `OrderShipped` |
| `PedidoEntregado` | `OrderDelivered` |
| `PedidoDevuelto` | `OrderReturned` |
