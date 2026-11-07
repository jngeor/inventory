# ADR-0015: Spring Cloud Gateway como punto de entrada

* **Estado**: Aceptado
* **Fecha**: 2026-11-07
* **Ticket**: KOAL-4

## Contexto

El C4 define un punto de entrada único que enruta por path hacia los cuatro microservicios, pero dejaba la tecnología sin decidir. El proyecto se despliega en dos formas: Docker Compose y Kubernetes local con kind (`docs/README.md` 5). El punto de entrada debe funcionar en ambas para que el flujo sea el mismo en todos los entornos.

## Decisión

* **Spring Cloud Gateway es el punto de entrada único**, en su variante reactiva, como un contenedor más.
* **Solo enruta por path.** No tiene lógica de negocio ni llama a varios servicios para combinar respuestas: el panel de alertas se combina en el cliente (`docs/README.md` 4.1).
* **No reemplaza la validación del token.** Reenvía el `Authorization` sin cambios y cada servicio valida el JWT (ADR-0013).
* **Participa en las trazas** para que la petición se vea desde su entrada (ADR-0014).
* **Las rutas son configuración**, por entorno, sin direcciones fijas.

## Alternativas consideradas

| Alternativa | Por qué no |
|---|---|
| **Ingress de Kubernetes** | No existe en Docker Compose, así que desarrollo necesitaría otra solución. |
| **Nginx o Traefik** | Funcionan en ambos despliegues y consumen menos, pero suman un componente fuera del stack Java, con su propia configuración y métricas. |
| **Kong** | Trae más funciones de las que se necesitan y requiere operar un producto más. |
| **Sin gateway** (el cliente llama a cada servicio) | El cliente tendría que conocer la dirección de cada servicio, y no habría un único punto de entrada. |

## Consecuencias

**Positivas**
* Es la misma tecnología del resto (Java 21, Spring, WebFlux) y hereda sus métricas y trazas.
* Funciona igual en Docker Compose y en kind.
* Deja un lugar natural para futuras políticas de entrada.

**Negativas / costos aceptados**
* Es un contenedor Java más que construir, desplegar y mantener, y consume más memoria que un proxy.
* Agrega un salto de red a cada petición, que cuenta en la latencia de R1.
* Es un punto único de entrada: sin réplicas, si cae no entra nadie. Como no guarda estado, se puede replicar.
* En kind, el gateway debe exponerse con un Service o un Ingress mínimo, sin reglas de enrutamiento propias.

**Cómo se verifica**: escenario R1 de `quality-attributes.md`, medido a través del gateway; test de rutas; S1 sigue exigiendo el 401 en cada servicio.

## Referencias

* `docs/architecture/c4-model.md`, nivel 2
* `docs/README.md` 4.1, 4.4, 5
* ADR-0013, ADR-0014
