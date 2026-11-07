# ADR-0001: Descomponer el sistema en cuatro microservicios por contexto acotado

* **Estado**: Aceptado
* **Fecha**: 2026-10-31
* **Ticket**: KOAL-1 (documentado en KOAL-4)

## Contexto

El sistema cubre maestro de productos, control de stock y kardex, ciclo de vida de pedidos y avisos al cliente (`docs/vision.md` 3). Estas áreas tienen reglas, ritmos de cambio y necesidades de datos distintas:

* El kardex necesita reportes y auditoría (core, `docs/architecture/context-map.md` 1).
* Los pedidos tienen una máquina de estados y una expiración a 48 h.
* El catálogo es un CRUD simple.
* Las notificaciones dependen de proveedores externos que pueden fallar.

Además, uno de los objetivos del proyecto es servir como **referencia completa de arquitectura de microservicios** en Java/Spring (`docs/vision.md` 2).

## Decisión

Dividimos el sistema en **cuatro microservicios**, uno por contexto acotado: **Catálogo**, **Inventario**, **Órdenes** y **Notificaciones** (`docs/README.md` 4.1).

* Cada uno es una aplicación Spring Boot que se despliega por separado, con su propia BD (ADR-0003) y su propia arquitectura interna hexagonal (ADR-0002).
* **No hay microservicio de Alertas.** Cada servicio que origina alertas (Inventario, Órdenes) las guarda y las expone en su propio endpoint de "alertas activas". El panel del administrador combina las dos fuentes en el cliente (`docs/README.md` 4.3).
* **Catálogo se consulta de forma síncrona** (REST + Resilience4j) desde Inventario y Órdenes, sin caché local ni eventos de producto por ahora.
* **Órdenes e Inventario se coordinan solo por eventos** (ADR-0005).

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Monolito modular** (un desplegable con módulos por contexto) | Sería más simple de operar y suficiente para el volumen actual. Se descarta porque el objetivo explícito del proyecto es ejercitar microservicios de punta a punta: despliegue independiente, mensajería, trazabilidad distribuida y resiliencia entre procesos. Si ese objetivo cambiara, sería la opción a reconsiderar. |
| **Menos servicios** (ej. Órdenes + Notificaciones juntos) | Notificaciones depende de proveedores externos lentos o caídos, y aislarlo evita que un fallo de email afecte al ciclo del pedido. Además es un consumidor puro, trivial de separar. |
| **Microservicio de Alertas dedicado** | Con solo dos fuentes de alertas no se justifica un servicio más, con su BD y su despliegue. Se reconsidera si aparecen más fuentes. |
| **Separar Inventario en "Stock" y "Kardex"** | El kardex y el stock cambian en la misma transacción (cada movimiento afecta al saldo). Separarlos obligaría a una consistencia eventual dentro del core, sin ningún beneficio. |

## Consecuencias

**Positivas**
* Los límites del código coinciden con los del dominio (context-map); cada servicio tiene un modelo pequeño y propio.
* Inventario, el core, puede invertir en CQRS sin arrastrar a los demás (ADR-0004).
* Los fallos quedan aislados: Notificaciones o Catálogo caídos no impiden que se registren pedidos ni que la saga avance (quality-attributes D1, D2).

**Negativas / costos aceptados**
* Costo operativo alto para el tamaño del sistema: 4 servicios, 5 BD, Kafka, Kafka Connect, Keycloak y el stack de observabilidad.
* Consistencia eventual entre Órdenes e Inventario, con su complejidad (saga, idempotencia, DLQ).
* Catálogo es una dependencia síncrona: si cae, no se registran pedidos ni guías (mitigado con circuit breaker, quality-attributes D2).
* Las pruebas de punta a punta requieren levantar todo el stack (Testcontainers / Docker Compose).

**Cómo se verifica**: cada servicio tiene su propio build, imagen y BD; no hay código de dominio compartido entre servicios (context-map, regla 3); tests de contrato entre productores y consumidores.

## Referencias

* `docs/README.md` 4.1, 4.3
* `docs/architecture/context-map.md`
* `docs/architecture/c4-model.md`, nivel 2
* `docs/vision.md` 2 y 3
