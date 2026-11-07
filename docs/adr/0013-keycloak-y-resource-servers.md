# ADR-0013: Keycloak como proveedor de identidad y cada servicio como resource server

* **Estado**: Aceptado
* **Fecha**: 2026-10-31
* **Ticket**: KOAL-4

## Contexto

El sistema tiene administradores y clientes, y más roles podrían aparecer (`docs/vision.md` 4). La identidad es un subdominio genérico (context-map) que no conviene construir. Hay que decidir quién emite los tokens y quién los valida.

## Decisión

* **Keycloak gestiona la identidad y emite los tokens** (OAuth2/OIDC). Corre con su propia BD (ADR-0003).
* **Cada microservicio es un resource server y valida el JWT por sí mismo**: firma, emisor y vencimiento. El gateway no reemplaza esta validación (ADR-0015).
* **Se valida localmente con las claves públicas de Keycloak**, sin consultarlo en cada petición.
* **La autorización es por roles.** Además, en Órdenes, el `customerId` se toma del `sub` del token, nunca del cuerpo de la petición.
* **La duración de los tokens se configura en el realm de Keycloak, por entorno.** Los valores iniciales son los de Keycloak: access token de 5 minutos y sesión de 30 minutos de inactividad. Los servicios no conocen estos valores: solo validan el vencimiento que trae el token.
* **Un pedido ajeno responde 404** y una acción de administrador sin el rol responde **403**, con un registro de auditoría en ambos casos. Por ahora ese registro va en los logs, con un campo que lo identifica.
* **Solo los endpoints de salud y métricas quedan sin autenticar**, en una lista explícita en la configuración.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Validar solo en el gateway** | Cualquier acceso que llegue a un servicio sin pasar por el gateway entraría sin control, y cada servicio confiaría en encabezados que no puede verificar. |
| **Validar cada token contra Keycloak** (introspección) | Agrega una llamada por petición y vuelve a Keycloak una dependencia síncrona de todos los flujos. |
| **Autenticación propia en un microservicio** | Construir contraseñas, sesiones y tokens no aporta valor y es riesgoso. |
| **Proveedor gestionado** (Auth0, Cognito) | No corre en local y depende de un proveedor externo, cuando el proveedor de nube sigue sin definir (ADR-0003). |

## Consecuencias

**Positivas**
* Ningún servicio depende de otro para decidir si acepta una petición.
* Si Keycloak cae, los tokens ya emitidos siguen validándose mientras se conserven las claves y no venzan.
* Agregar un rol no cambia el modelo de seguridad, solo las reglas de autorización.

**Negativas / costos aceptados**
* La configuración de seguridad se repite en los cuatro servicios.
* **Los roles de Keycloak no van en un claim estándar** (`realm_access.roles`), así que cada servicio necesita un convertidor. Todos quedan acoplados a ese formato, lo cual es esperable en una relación Conformist (context-map R5).
* Un token no se puede revocar antes de que venza. Por eso dura solo 5 minutos: un rol retirado sigue vigente, como máximo, ese tiempo.
* **Importar un realm no modifica uno que ya existe**: en un entorno ya creado, cambiar la duración exige hacerlo también en Keycloak, por consola o por su API.
* La auditoría de accesos denegados se conserva lo que dure la retención de logs: 14 días en desarrollo (ADR-0014). Si hace falta guardarla más tiempo, se hará una tabla por servicio cuando exista producción.
* Kafka no pasa por esta validación. El token no viaja en los eventos, y estos se confían por ser internos.

**Cómo se verifica**: escenarios S1 y S2 de `quality-attributes.md`.

## Referencias

* `docs/README.md` 5
* `docs/architecture/context-map.md` R5
* `docs/architecture/quality-attributes.md` S1, S2
* ADR-0003, ADR-0015
