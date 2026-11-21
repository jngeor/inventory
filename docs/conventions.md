# Convenciones del repositorio

* **Estado**: Aceptado
* **Fecha**: 2026-11-16
* **Ticket**: KOAL-12

Cómo se trabaja en este repositorio: idioma, estructura, ramas, commits, PR, formato del código, contratos, ADRs y secretos. Las convenciones que ya están escritas en otro documento no se repiten aquí: se enlazan en la sección 10. Si una regla de este documento contradice a otro, se corrige uno de los dos en el mismo PR.

## 1. Idioma

| Qué | Idioma | Detalle |
|---|---|---|
| Documentación (`docs/`, ADRs, README) | Español | |
| Mensajes de commit y descripciones de PR | Español | El tipo de commit va en inglés (4) |
| Código: clases, métodos, propiedades, paquetes | Inglés | Con los términos de `docs/glosario.md` |
| Comentarios y Javadoc | Inglés | Como el código que describen |
| Rutas, campos y parámetros de la API | Inglés | `docs/api/README.md`, Rutas y operaciones |
| Nombres de eventos y topics | Inglés | ADR-0024 |
| Tablas, columnas, colecciones y migraciones | Inglés | `docs/architecture/data-model.md` 2.1, 4 y 5 |
| Mensajes de error para el cliente (`title`, `detail`) | Español | `docs/api/README.md`, Errores; `code` en inglés |
| Mensajes de log (`message`) | Español | `docs/strategies/observability.md` 6.1 |

## 2. Estructura del repositorio

Es la estructura objetivo. Hoy solo existe `docs/`; cada carpeta se crea con el ticket que la necesita, en este lugar y con este nombre.

```text
inventory/
├── README.md               ← qué es el proyecto y cómo levantarlo
├── pom.xml                 ← POM padre: solo versiones y plugins (ADR-0018)
├── catalog/                ← un módulo Maven por desplegable (ADR-0018)
├── inventory/
├── orders/
├── notifications/
├── gateway/
├── e2e/                    ← tests de punta a punta; no es un desplegable (testing.md 6)
├── deploy/
│   ├── docker-compose.yml  ← entorno local completo
│   ├── keycloak/           ← exportación del realm koala (security.md 2.1)
│   ├── kafka-connect/      ← configuración de los conectores de Debezium
│   ├── observability/      ← Collector, Tempo, Loki, Prometheus y grafana/ (observability.md 8)
│   └── k8s/                ← manifiestos o charts para kind
├── perf/                   ← scripts de k6 y procedimientos de caos (testing.md 7)
├── docs/
├── .github/workflows/      ← CI (testing.md 9)
├── .editorconfig
├── .gitattributes
├── .gitignore
└── .env.example
```

* **Dentro de cada servicio**, los paquetes siguen ADR-0002 y `docs/architecture/c4-model.md` nivel 3. Las migraciones de Flyway viven en el módulo del servicio (ADR-0020).
* **Ningún módulo depende de otro**, `e2e` incluido: solo de los contratos y de las imágenes (ADR-0018).
* **La estructura de `deploy/k8s/`** (Helm o Kustomize) se decide cuando se arme el despliegue en kind.

## 3. Tickets y ramas

* **Un ticket = una rama = un PR.** El ticket se escribe `KOAL-N`, con número sin ceros a la izquierda: `KOAL-7`, no `KOAL-07`.
* **La rama se llama `feature/KOAL-N`** y sale de `main` actualizado. Se usa el mismo prefijo para cualquier tipo de trabajo: el tipo lo dice el commit (4).
* **Una rama no sale de otra rama de ticket.** Si un ticket necesita lo de otro, espera a que ese se mergee a `main`.

## 4. Commits

Se usa [Conventional Commits](https://www.conventionalcommits.org/es/v1.0.0/) con el ticket al inicio de la descripción:

```text
tipo(alcance): KOAL-N descripción

Cuerpo opcional: qué cambia y por qué, en líneas de hasta 72 caracteres.
```

| Tipo | Cuándo |
|---|---|
| `feat` | Funcionalidad nueva, aunque incluya su contrato, sus tests y su documentación |
| `fix` | Corrección de un error, en código o en un documento ya mergeado |
| `docs` | Solo documentación: `docs/`, ADRs, contratos que todavía no tienen código, README |
| `test` | Solo tests, sin cambiar el código probado |
| `refactor` | Cambio de código que no cambia el comportamiento |
| `build` | POM, Dockerfiles, CI y `deploy/` |
| `chore` | Mantenimiento del repo: `.gitignore`, `.editorconfig`, versiones de herramientas |

* **El alcance es opcional** y nombra el módulo: `catalog`, `inventory`, `orders`, `notifications`, `gateway`, `e2e` o `deploy`. Se omite cuando el cambio cruza varios módulos o solo toca `docs/`.
* **La descripción** va en español, en minúscula, sin punto final y en menos de 72 caracteres contando el prefijo.
* **No se usa `!` ni `BREAKING CHANGE`**: un cambio incompatible de la API o de un evento no se hace sobre el contrato existente, sino con `/api/v2` o un evento nuevo (ADR-0019, ADR-0024).

Ejemplos:

```text
docs: KOAL-12 convenciones del repositorio
feat(orders): KOAL-15 registro de pedidos
fix(inventory): KOAL-21 saldo del kardex al reconstruir la proyección
build: KOAL-14 pipeline de CI por módulo
```

## 5. Pull requests y `main`

* **Antes de abrir el PR, los commits de la rama se juntan en uno** (squash local), con el formato de la sección 4. El PR se mergea con **merge commit**, así `main` muestra un commit por ticket y el merge que lo trajo.
* **El título del PR** es el mismo que el del commit. La descripción resume qué cambia, qué decisiones o ADRs incluye y qué queda pendiente.
* **Antes del PR** se corren las verificaciones locales que apliquen: `mvn verify` en los módulos que cambiaron, y `redocly lint` y `asyncapi validate` si cambió `docs/api/`. En CI corren los jobs de `docs/strategies/testing.md` 9; **un PR no se mergea con un job en rojo**.
* **Protección de `main`** (regla de rama en GitHub, que aplica también al administrador):
  * Solo se cambia por PR: sin push directo.
  * Sin force push ni borrado de la rama.
  * Los jobs de CI son obligatorios para mergear, en cuanto existan.
  * Sin mínimo de aprobaciones, mientras el repo lo mantenga una sola persona.
* **El force push solo se usa en la rama propia**, con `--force-with-lease`, por ejemplo para corregir el mensaje de un commit ya subido.

## 6. Código Java

* **Formato con Spotless y Google Java Format en estilo AOSP** (sangría de 4 espacios). Spotless se configura en el POM padre: `mvn spotless:apply` formatea y `spotless:check` corre dentro de `mvn verify`, así que el build falla si un archivo no está formateado. Spotless también ordena los imports y quita los que no se usan.
* **Nombres** con los términos de `docs/glosario.md`: PascalCase para clases y camelCase para métodos y propiedades.
* **Comentarios y Javadoc en inglés.** Un comentario explica por qué, no qué: lo que el código ya dice no se repite.
* **Paquetes** según ADR-0002 y `docs/architecture/c4-model.md` nivel 3, verificados por las reglas de ArchUnit de `docs/strategies/testing.md` 5.
* **Tests**: `*Test` sin contenedores y `*IT` con contenedores (`docs/strategies/testing.md` 2).
* **Logs**: formato, niveles y datos prohibidos en `docs/strategies/observability.md` 6.
* **Valores configurables** (reintentos, plazos, umbrales) van en propiedades, nunca fijos en el código (`docs/README.md` 5.1).

## 7. Contratos y decisiones

* **Todo cambio de API o de evento empieza en el YAML** de `docs/api/`, en el mismo PR que el código (ADR-0021). Las reglas de rutas, tipos, errores y versiones están en `docs/api/README.md`.
* **Cada decisión de arquitectura lleva un ADR** con `docs/adr/template.md`, numerado de forma correlativa y agregado al índice `docs/adr/README.md` en el mismo PR.
* **Un ADR aceptado no cambia su decisión**: si cambia o crece, se escribe un ADR nuevo con `Amplía:` o `Reemplaza:`, y el anterior cambia su estado; si hace falta, deja en la parte afectada una remisión corta al ADR nuevo, sin reescribir su decisión. Una precisión que no cambia la decisión se escribe en el mismo ADR, con la fecha y el ticket en su estado, y una errata se corrige sin nota. El detalle está en `docs/adr/README.md`.
* **Los términos nuevos del dominio** se agregan a `docs/glosario.md` antes de usarlos en el código o en los contratos.

## 8. Configuración y secretos

* **Ningún secreto entra al repositorio**: ni contraseñas, ni secretos de clients, ni credenciales de Kafka.
* **`.env` no se versiona.** El repo tiene un `.env.example` con todas las variables y valores falsos; para levantar el entorno local se copia a `.env` y se completa.
* **Fuera de local**, los secretos llegan como variables de entorno, distintos por servicio y por entorno; en kind, como `Secret` de Kubernetes (`docs/strategies/security.md` 9).
* **El realm de Keycloak versionado** solo tiene usuarios y valores de desarrollo, que no son secretos (`docs/strategies/security.md` 3.2 y 9).

## 9. Archivos de configuración del repositorio

* **`.editorconfig`**: UTF-8, fin de línea LF, salto de línea al final del archivo y sin espacios al final de la línea. Sangría de 4 espacios en Java, XML y SQL; de 2 en YAML, JSON y Markdown.
* **`.gitattributes`**: `* text=auto eol=lf`, para que Git guarde LF aunque se trabaje en Windows. Los scripts `.cmd` y `.bat`, si los hay, quedan en CRLF.
* **`.gitignore`**: `target/`, archivos de los IDE (`.idea/`, `*.iml`, `.vscode/`), `.env`, logs locales y archivos del sistema operativo (`.DS_Store`, `Thumbs.db`).

## 10. Dónde está cada convención

| Tema | Documento |
|---|---|
| Lenguaje ubicuo, español e inglés | `docs/glosario.md` |
| API REST: rutas, tipos, listas, errores, cambios | `docs/api/README.md` |
| Eventos: formato, sobre, versiones | `docs/api/README.md`, Eventos; ADR-0024 |
| PostgreSQL: nombres, tipos, identificadores, auditoría | `docs/architecture/data-model.md` 2 |
| Tablas técnicas: outbox, idempotencia, shedlock | `docs/architecture/data-model.md` 3 |
| Migraciones de Flyway | `docs/architecture/data-model.md` 4; ADR-0020 |
| MongoDB | `docs/architecture/data-model.md` 5 |
| Paquetes y dependencias entre capas | ADR-0002; `docs/architecture/c4-model.md` nivel 3 |
| Tests: niveles, nombres, ArchUnit, CI | `docs/strategies/testing.md` |
| Logs, métricas y trazas | `docs/strategies/observability.md` |
| Roles, tokens y secretos | `docs/strategies/security.md` |
| Reintentos | `docs/README.md` 5.1; ADR-0010 |
| Formato de un ADR | `docs/adr/template.md` |

## Referencias

* ADR-0002, ADR-0018, ADR-0019, ADR-0020, ADR-0021, ADR-0024
* `docs/strategies/testing.md` 9
* `docs/strategies/security.md` 9
