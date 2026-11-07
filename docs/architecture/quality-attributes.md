# Atributos de Calidad

Escenarios de calidad medibles para validar que la arquitectura cumple lo que promete. Cada escenario sigue el formato del SEI: **fuente → estímulo → artefacto → entorno → respuesta → medida**. Complementa a `docs/README.md` (secciones 4 y 5), a `docs/architecture/context-map.md` y a la política de reintentos (README 5.1).

## 1. Convenciones

* **Entorno de referencia**: el stack completo en Docker Compose en una máquina de desarrollo (todos los microservicios, Kafka, Kafka Connect/Debezium, PostgreSQL, MongoDB (lectura de Inventario), Keycloak y el stack de observabilidad), con un volumen de datos de prueba de **1 000 productos y 100 000 movimientos de kardex**. Las medidas de rendimiento solo son comparables en este entorno; en Kubernetes (kind) se toman como referencia.
* **Los valores son metas iniciales.** Se ajustan con las primeras mediciones reales y cada cambio queda registrado en este documento. Ninguna medida es "rápido" o "seguro" sin un número.
* **Prioridad**: **(A)** alta, si falla, la arquitectura no cumple su propósito. **(M)** media, importante pero negociable.
* **Cada escenario dice cómo se verifica**: test automatizado, prueba de carga (k6), prueba de caos (detener contenedores) o revisión manual guiada.

## 2. Resumen

| Id | Atributo | Escenario | Prioridad |
|---|---|---|---|
| D1 | Disponibilidad | Inventario caído mientras se registran pedidos | A |
| D2 | Disponibilidad | Catálogo caído | A |
| D3 | Disponibilidad | El conector de Debezium falla | A |
| D4 | Disponibilidad | Un movimiento de stock no se puede proyectar en la BD de lectura | A |
| R1 | Rendimiento | Registro de pedido bajo carga | A |
| R2 | Rendimiento | Saga de reserva de stock de punta a punta | M |
| R3 | Rendimiento | Consulta de kardex y retraso del lado de lectura | A |
| S1 | Seguridad | Petición sin token o con token inválido | A |
| S2 | Seguridad | Cliente intenta acceder a un pedido ajeno o a una acción de administrador | A |
| S3 | Seguridad | Movimiento de kardex con fecha manipulada | A |
| O1 | Observabilidad | Pedido "atascado": diagnóstico entre servicios | A |
| O2 | Observabilidad | Un mensaje termina en la DLQ | A |
| M1 | Modificabilidad | Nuevo tipo de documento de compra o de movimiento | A |
| M2 | Modificabilidad | Reemplazar el proveedor de SMS | M |
| M3 | Modificabilidad | Agregar un campo a un evento publicado | M |

## 3. Disponibilidad

### D1. Inventario caído mientras se registran pedidos (A)

| Parte | Detalle |
|---|---|
| Fuente | Fallo de infraestructura (caída del proceso o del contenedor de Inventario). |
| Estímulo | Inventario no está disponible durante **10 minutos** mientras los clientes siguen registrando pedidos. |
| Artefacto | Órdenes, Inventario, Kafka (saga de stock, README 4.2). |
| Entorno | Operación normal; 100 pedidos registrados durante la caída. |
| Respuesta | Órdenes sigue aceptando pedidos, que quedan en `REGISTERED`, porque no depende de forma síncrona de Inventario (context-map, regla 4). Cuando Inventario vuelve, consume los `OrderRegistered` pendientes desde su último offset y resuelve cada reserva. |
| Medida | **100 %** de los pedidos registrados durante la caída responden 201. **0** eventos perdidos y **0** reservas duplicadas, verificado contra `StockReservation` (único por `orderId`). Todos los pedidos pendientes quedan en `RESERVED` o `PENDING` en menos de **2 minutos** desde que Inventario vuelve a estar listo. |
| Verificación | Prueba de caos: `docker stop` de Inventario, carga con k6 y conciliación con SQL. |

### D2. Catálogo caído (A)

| Parte | Detalle |
|---|---|
| Fuente | Fallo de infraestructura en Catálogo. |
| Estímulo | Catálogo deja de responder (caído o con timeouts) mientras se registran pedidos y guías de remisión. |
| Artefacto | Clientes REST hacia Catálogo en Órdenes e Inventario (Resilience4j, README 5.1). |
| Entorno | Operación normal. |
| Respuesta | Las operaciones que necesitan Catálogo fallan de forma controlada con 503 y un mensaje claro, sin dejar datos a medias. El circuit breaker se abre y deja de llamar a Catálogo. El resto del sistema sigue funcionando: la saga en curso, las consultas de kardex, las transiciones del administrador y las notificaciones. |
| Medida | Con el circuito abierto, el 503 se devuelve en menos de **100 ms** (p95), sin esperar timeouts. Cada petición hace como máximo **3 intentos** a Catálogo antes de abrir el circuito. **0** pedidos o guías guardados con datos incompletos. Cuando Catálogo vuelve, el circuito se cierra solo en menos de **60 s**. |
| Verificación | Test de integración con Testcontainers + Toxiproxy (o detener el contenedor), y métricas de Resilience4j en Prometheus. |

### D3. El conector de Debezium falla (A)

| Parte | Detalle |
|---|---|
| Fuente | Fallo de Kafka Connect, o error persistente al leer el WAL o al publicar. |
| Estímulo | El conector del outbox de Órdenes o de Inventario agota sus **5 reintentos** y queda en `FAILED` (README 5.1). |
| Artefacto | Tabla outbox, Debezium/Kafka Connect, alertas en Prometheus/Grafana. |
| Entorno | Operación normal; los servicios siguen escribiendo en sus outbox. |
| Respuesta | Los servicios siguen aceptando comandos y los eventos se acumulan en el outbox y en el WAL. Se dispara una alerta operativa. Tras el reinicio manual del conector, se publican todos los eventos pendientes en orden. |
| Medida | La alerta aparece en Grafana en menos de **2 minutos** desde que el conector queda en `FAILED`. **0** eventos perdidos y orden preservado por clave de mensaje (por producto para los movimientos de stock, README 3.1). No hay reintentos infinitos: el conector se detiene tras el máximo configurado. |
| Verificación | Prueba de caos: forzar un error en el conector y verificar la alerta, los conteos del outbox frente a los mensajes publicados y el orden por clave de mensaje. |

### D4. Un movimiento de stock no se puede proyectar en la BD de lectura (A)

| Parte | Detalle |
|---|---|
| Fuente | Fallo del proyector del lado lectura de Inventario (error no recuperable o reintentos agotados). |
| Estímulo | Un `StockMovementRecorded` del producto X termina en la DLT mientras siguen llegando movimientos de X y de otros productos. |
| Artefacto | Proyector CQRS de Inventario, `ProductStockView`/`KardexEntry` (MongoDB), alerta `SYNC_FAILURE` (README 3.1). |
| Entorno | Operación normal, con una persona monitoreando las alertas. |
| Respuesta | La proyección **no se detiene**: los movimientos siguientes de X y de los demás productos se siguen aplicando. X queda marcado `outOfSync` y las consultas lo informan. Se genera `SYNC_FAILURE`. La persona corrige la causa, reprocesa el evento y reconstruye la proyección de X desde la BD de escritura. |
| Medida | Retraso de los productos de particiones atendidas por otros hilos: **sin cambio** respecto de R3. Los demás, hasta **7 s** adicionales mientras duran los reintentos (1 s + 2 s + 4 s), que retienen la partición para no romper el orden por producto. X marcado `outOfSync` en menos de **5 s** desde que el evento va a la DLT. Alerta visible en menos de **2 minutos**. **Resolución en 24 h o menos**, con alerta de escalamiento a las **20 h** si sigue activa. Tras la reconstrucción, el saldo de X en la lectura coincide **100 %** con el `physicalStock` de la escritura. |
| Verificación | Test de integración que fuerza el fallo de un evento de X y verifica la marca, que los eventos posteriores se aplican y que la reconstrucción deja el saldo igual al de la BD de escritura. El plazo de 24 h se mide con la métrica de antigüedad de las alertas `SYNC_FAILURE` activas. |

## 4. Rendimiento

### R1. Registro de pedido bajo carga (A)

| Parte | Detalle |
|---|---|
| Fuente | Clientes autenticados. |
| Estímulo | **10 pedidos por segundo** sostenidos durante **10 minutos**, con 1 a 5 ítems por pedido. Está por encima del volumen esperado: es una meta aceptada por ahora, no una previsión de negocio. |
| Artefacto | API de Órdenes (registro: consulta a Catálogo + escritura de `Order` y del outbox en una transacción). |
| Entorno | Entorno de referencia, con carga normal. |
| Respuesta | El pedido se registra y se responde sin esperar la verificación de stock, que es asíncrona. |
| Medida | Latencia p95 < **300 ms**, p99 < **800 ms** y tasa de error < **0,1 %**. |
| Verificación | Script k6 versionado en el repo, con los resultados comparados en cada versión. |

### R2. Saga de reserva de stock de punta a punta (M)

| Parte | Detalle |
|---|---|
| Fuente | Cliente que registra un pedido. |
| Estímulo | Se registra un pedido con stock disponible. |
| Artefacto | Saga Órdenes → Kafka → Inventario → Kafka → Órdenes, incluidos los dos conectores de Debezium. |
| Entorno | Entorno de referencia, con la carga de R1. |
| Respuesta | El pedido pasa de `REGISTERED` a `RESERVED`. |
| Medida | El tiempo desde la respuesta 201 hasta que el pedido está en `RESERVED` es p95 < **2 s** y p99 < **5 s**. |
| Verificación | Se mide con la diferencia de tiempo entre `registeredAt` y la transición a `RESERVED` en `statusHistory`, y con la duración de la traza completa (O1). |

### R3. Consulta de kardex y retraso del lado de lectura (A)

| Parte | Detalle |
|---|---|
| Fuente | Administrador. |
| Estímulo | Consulta el kardex de un producto con **10 000 movimientos** en el rango de un año, paginado de a 100 filas. |
| Artefacto | Lado lectura de Inventario (`KardexEntry`, BD de lectura en MongoDB) y la sincronización CQRS (README 3.1). |
| Entorno | Entorno de referencia, mientras se registran movimientos a 20 por segundo. |
| Respuesta | Se devuelve la página con el saldo acumulado ya calculado (no se recalcula en la consulta). |
| Medida | Latencia de la consulta p95 < **500 ms**. El retraso entre que un movimiento se confirma en la BD de escritura y aparece en la BD de lectura es p95 < **1 s** y p99 < **3 s**. |
| Verificación | k6 para la consulta. El retraso se mide como la diferencia entre el timestamp del evento y el de la proyección, expuesta como métrica en Prometheus. |

## 5. Seguridad

### S1. Petición sin token o con token inválido (A)

| Parte | Detalle |
|---|---|
| Fuente | Actor externo no autenticado, o con un token vencido, mal firmado o de otro emisor. |
| Estímulo | Llama a cualquier endpoint de negocio de cualquier microservicio. |
| Artefacto | La configuración de resource server de cada microservicio (Keycloak, context-map R5). |
| Entorno | Operación normal. |
| Respuesta | Se rechaza la petición antes de ejecutar cualquier lógica de negocio, y el rechazo queda en el log. |
| Medida | **100 %** de los endpoints de negocio responden 401 sin token, con token vencido o con firma inválida. **0** efectos en la BD. Solo los endpoints de salud y métricas quedan sin autenticar, y la lista está explícita en la configuración. |
| Verificación | Test automatizado que recorre todos los endpoints registrados (no una lista escrita a mano) en cada microservicio, ejecutado en CI. |

### S2. Cliente intenta acceder a un pedido ajeno o a una acción de administrador (A)

| Parte | Detalle |
|---|---|
| Fuente | Cliente autenticado con un token válido. |
| Estímulo | (a) Consulta o cancela un pedido de otro cliente. (b) Intenta procesar, enviar o entregar un pedido, registrar una guía de remisión o resolver una alerta. |
| Artefacto | Autorización en Órdenes e Inventario (roles de Keycloak + `customerId` = `sub`). |
| Entorno | Operación normal. |
| Respuesta | (a) Se responde 404, como si el pedido no existiera, para no revelar qué ids existen. (b) Se responde 403. En ambos casos queda un registro de auditoría en los logs, con un campo que lo identifica, el `sub` y el `traceId`; se conserva lo que dure la retención de logs (ADR-0013). |
| Medida | **100 %** de los intentos bloqueados y **0** cambios de estado. Los casos (a) y (b) están cubiertos por tests en cada caso de uso que recibe un `orderId` o requiere el rol de administrador. |
| Verificación | Tests de integración con tokens de prueba de dos clientes y un administrador (Keycloak en Testcontainers). |

### S3. Movimiento de kardex con fecha manipulada (A)

| Parte | Detalle |
|---|---|
| Fuente | Usuario interno con permisos de registro (posible fraude para encubrir robo o pérdida). |
| Estímulo | Registra un movimiento cuya fecha de documento difiere en más de **48 h** de su fecha de creación (README 2.2). |
| Artefacto | Dominio de Inventario (`StockMovement.unusual`, `Alert` `UNUSUAL_MOVEMENT`). |
| Entorno | Operación normal. |
| Respuesta | El movimiento se registra marcado como inusual y se genera una alerta. El movimiento no se puede editar ni borrar: solo se corrige con un ajuste de stock (`AdjustStock`), que exige motivo, guarda su autor y genera una alerta `STOCK_ADJUSTMENT`. |
| Medida | **100 %** de los movimientos fuera del umbral quedan marcados, con **0** falsos negativos en los tests de borde (47 h 59 min, 48 h, 48 h 1 min, en ambas direcciones). La alerta es visible en el panel en menos de **5 s**. **0** endpoints que permitan modificar o eliminar movimientos. **100 %** de los ajustes con motivo, autor y alerta. |
| Verificación | Tests unitarios del dominio para los bordes, más un test de arquitectura o de API que verifique que no hay operaciones de actualización o borrado sobre `StockMovement`. |

## 6. Observabilidad

### O1. Pedido "atascado": diagnóstico entre servicios (A)

| Parte | Detalle |
|---|---|
| Fuente | Administrador o desarrollador. |
| Estímulo | Un pedido lleva más de 10 minutos en `REGISTERED` y se quiere saber por qué. |
| Artefacto | OpenTelemetry (trazas), logs JSON, métricas (README 5). |
| Entorno | Operación normal o degradada. |
| Respuesta | A partir del `orderId` se encuentra el `traceId` y se ve la traza completa: petición HTTP → Órdenes → Inventario → Órdenes. Debezium y Kafka no aparecen como pasos propios, sino como el tiempo entre la escritura en el outbox y el consumo del evento (ADR-0014). Esa traza muestra en qué salto se detuvo y los logs de ese salto, filtrados por el mismo `traceId`. Si la traza termina en la escritura del outbox, se revisa el conector (D3). |
| Medida | **100 %** de los logs de negocio en JSON con `traceId`. La traza conserva su continuidad en los saltos asíncronos (Kafka), es decir, una sola traza por flujo y no una por servicio. Todas las trazas de un pedido se encuentran por `orderId`, porque procesar, enviar y entregar son flujos separados. El punto de falla se localiza en menos de **5 minutos** sin acceder a las BD ni a los contenedores. |
| Verificación | Revisión guiada con un fallo inyectado (por ejemplo, el consumidor de Inventario detenido), más un test automatizado de punta a punta que verifique que el header `traceparent` del mensaje en Kafka lleva el mismo `traceId` de la petición HTTP que lo originó. |

### O2. Un mensaje termina en la DLQ (A)

| Parte | Detalle |
|---|---|
| Fuente | Fallo de un consumidor (error no recuperable o reintentos agotados, README 5.1). |
| Estímulo | Un mensaje se publica en `<topic>.DLT`. |
| Artefacto | Consumidores de Kafka de los 4 microservicios, Prometheus/Grafana. |
| Entorno | Operación normal. |
| Respuesta | Se dispara una alerta operativa. El mensaje en la DLQ conserva el payload original, los headers (incluido `traceparent`) y la causa del error (excepción, topic de origen, offset y número de intentos), para poder reprocesarlo a mano. |
| Medida | La alerta aparece en Grafana en menos de **2 minutos**. **100 %** de los mensajes en la DLQ tienen los headers de diagnóstico. Hay un panel por topic DLT con el conteo de mensajes. |
| Verificación | Test de integración que fuerza un error no recuperable y verifica el contenido del mensaje en la DLT; la alerta se revisa en el dashboard versionado. |

## 7. Modificabilidad

### M1. Nuevo tipo de documento de compra o de movimiento (A)

| Parte | Detalle |
|---|---|
| Fuente | Negocio. |
| Estímulo | (a) Se agrega un nuevo tipo de documento de compra para las guías de remisión (README 2). (b) Se agrega un tipo de salida por merma, por daño o vencimiento, a `MovementType` (ej. `WRITE_OFF`, previsto en `domain-model.md`, Inventario → `StockMovement`). |
| Artefacto | Dominio de Inventario y su modelo de lectura. |
| Entorno | En desarrollo. |
| Respuesta | El cambio se hace solo dentro de Inventario. El kardex y los saldos funcionan con el nuevo tipo sin cambiar la lógica de cálculo. |
| Medida | **0** archivos cambiados en otros microservicios. **0** cambios incompatibles en la API pública (solo se agrega un valor). Sin migración de datos existentes. Se implementa y se prueba en **1 día** o menos. |
| Verificación | Revisión del diff del cambio real cuando ocurra; los tests del kardex se parametrizan por `MovementType`. |

### M2. Reemplazar el proveedor de SMS (M)

| Parte | Detalle |
|---|---|
| Fuente | Equipo de desarrollo. |
| Estímulo | Se reemplaza el adaptador de SMS que escribe en el log por un proveedor real. |
| Artefacto | Notificaciones (puerto `NotificationSender`, ACL de context-map R6). |
| Entorno | En desarrollo. |
| Respuesta | Se agrega un nuevo adaptador de salida y su configuración, sin tocar el dominio ni la capa de aplicación. |
| Medida | **0** cambios en los paquetes `domain` y `application`. Las reglas de ArchUnit siguen pasando. Los tests existentes pasan sin modificarse. Se implementa en **1 día** o menos. |
| Verificación | Reglas de ArchUnit en CI (el dominio no depende de adaptadores ni de frameworks) y revisión del diff. |

### M3. Agregar un campo a un evento publicado (M)

| Parte | Detalle |
|---|---|
| Fuente | Equipo de desarrollo. |
| Estímulo | Se agrega un campo opcional a `OrderRegistered` (por ejemplo, un comentario del cliente). |
| Artefacto | El Published Language entre Órdenes, Inventario y Notificaciones (context-map, sección 5 y regla 8). |
| Entorno | En producción, con consumidores desplegados en la versión anterior. |
| Respuesta | Los consumidores existentes siguen procesando los eventos ignorando el campo nuevo. Cada servicio se puede desplegar por separado, sin coordinación. |
| Medida | **0** mensajes en la DLQ por el cambio. **0** redespliegues obligatorios de los consumidores. Los tests de contrato del productor y de los consumidores pasan con la versión nueva y con la anterior. |
| Verificación | Tests de contrato entre microservicios en CI, y deserializadores configurados para ignorar campos desconocidos. |

## 8. Fuera de alcance por ahora

* **Escalabilidad horizontal**: el diseño la permite (consumidores agrupados por consumer group, ShedLock para el scheduler), pero no hay metas de escala hasta tener mediciones de R1–R3.
* **Recuperación ante desastres** (respaldos, RPO/RTO): fuera de alcance del entorno local.
* **Disponibilidad anual (SLA en "nueves")**: no tiene sentido en un entorno de desarrollo; los escenarios D1–D3 miden el comportamiento ante fallos concretos.
