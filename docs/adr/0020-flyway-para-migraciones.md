# ADR-0020: Flyway para las migraciones de PostgreSQL

* **Estado**: Aceptado
* **Fecha**: 2026-11-07
* **Ticket**: KOAL-4

## Contexto

Cada servicio tiene sus propias migraciones, sin depender de nada a nivel de instancia (ADR-0003). Falta elegir la herramienta. Las habituales usan JDBC, mientras que el acceso normal a datos es por R2DBC (ADR-0011). El esquema también incluye las tablas `outbox` y `shedlock`, de las que dependen Debezium y los jobs (ADR-0006, ADR-0012).

## Decisión

* **Cada servicio con PostgreSQL migra con Flyway**, usando archivos SQL versionados en su propio módulo.
* **Las migraciones corren al arrancar el servicio**, por JDBC. Ese driver se usa solo para esto: el acceso normal sigue siendo R2DBC.
* **Una migración aplicada no se edita.** Un cambio se hace con una migración nueva, y solo se avanza: no hay scripts de reversión.
* **Cada migración debe ser compatible con la versión anterior del servicio**, para poder desplegar sin detener todas las instancias.
* **MongoDB no tiene migraciones.** Sus modelos de lectura se regeneran desde la escritura (ADR-0007).
* **Keycloak gestiona su propio esquema.**

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Liquibase** | Es más potente, con reversiones y formatos propios, pero esas funciones no hacen falta aquí. El SQL directo es más simple de leer y revisar. |
| **Scripts manuales** | No registran qué se aplicó en cada entorno, y fallarían justo al promover de un entorno a otro. |
| **Generar el esquema desde las entidades** | Spring Data R2DBC no lo hace, y no daría control sobre índices ni sobre las tablas `outbox` y `shedlock`. |
| **Paso de migración separado en el despliegue** | Da más control, y es el camino si el arranque resulta riesgoso, pero agrega un paso en Docker Compose y en Kubernetes. |

## Consecuencias

**Positivas**
* El esquema de cada servicio está versionado junto a su código.
* Se migra igual en todos los entornos, y solo cambia la configuración (ADR-0003).
* Flyway coordina las migraciones: si arrancan varias instancias a la vez, solo una las aplica.

**Negativas / costos aceptados**
* Cada servicio configura dos conexiones a la misma BD: JDBC para migrar y R2DBC para operar.
* Sin reversiones, una migración errónea se corrige con otra migración.
* Una migración larga retrasa el arranque del servicio.
* Cambiar la tabla `outbox` afecta al conector de Debezium: esos cambios se coordinan con su configuración.

**Cómo se verifica**: los tests de integración arrancan con Testcontainers y aplican todas las migraciones desde cero; Flyway valida al arrancar que ninguna migración aplicada cambió.

## Referencias

* `docs/architecture/c4-model.md`, contenedores
* ADR-0003, ADR-0006, ADR-0007, ADR-0011, ADR-0012
