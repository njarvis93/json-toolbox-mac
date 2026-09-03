# Spec: ignorar claves y exportar el diff

Los dos últimos trozos de la Fase 5.

## Ignorar claves

**El problema.** Pides dos veces la misma respuesta a una API y no son iguales: `generadoEn`,
`requestId`, `version` cambian solas. Esas diferencias de ruido tapan la que se está buscando.
Medido sobre dos respuestas reales: 5 diferencias, de las que **1 era real**.

**Cómo.** `DiffOptions.ignoredKeys`, por **nombre y a cualquier profundidad**: `requestId` se
ignora esté donde esté. Por nombre y no por ruta completa a propósito — es lo cómodo, y quien
necesite distinguir `meta.requestId` de `datos.requestId` es un caso bastante más raro. Si
estorba, se añade la forma con ruta.

La lista se escribe en un popover del toolbar, separada por comas o saltos de línea, y se guarda
entre lanzamientos.

**Que se está ignorando algo se ve siempre**, y esto no es cosmético: el icono del toolbar pasa a
ojo tachado, la línea de resumen dice "ignorando N claves" y el volcado exportado lo lleva escrito.
Una comparación que esconde diferencias sin decirlo es peor que no tener la funcionalidad —
alguien acabaría fiándose de un "sin diferencias" que no era verdad.

Detalle: las claves son sensibles a mayúsculas, como en JSON. Ignorar no puede romper el
emparejado por clave de identidad, y hay un test que lo fija.

## Exportar

El final del camino de una comparación no es mirarla, es contársela a alguien. Dos formatos:

**Texto plano**, con las columnas alineadas a mano (sin alinear no se lee; hay un test que
comprueba que todas las flechas caen en la misma columna):

```
pedidoA.json  vs  pedidoB.json
2 diferencias · 1 añadida, 1 modificada

modificado  lineas[1].cantidad  2  →  3
añadido     lineas[0]           —  →  {"sku":"TL-7777","cantidad":1,"precio":59.00}
```

**Markdown**, tabla, para GitHub o Jira:

```
| Cambio | Ruta | A | B |
|---|---|---|---|
| modificado | `lineas[1].cantidad` | `2` | `3` |
```

Los contenedores se minifican para que quepan en una línea. Las barras verticales dentro de un
valor se escapan: sin eso partirían la fila en celdas de más, y hay un test que cuenta las barras
de cada fila.

Está en el toolbar de Comparar y en el menú Archivo. Copia al portapapeles; no escribe ficheros.

## Criterio de aceptación
1. `swift build` y `swift test` en verde. **Hecho**: 168/168 el 2026-09-02, 18 de ellos nuevos.
2. Dos respuestas de API con `generadoEn` y `requestId`: 5 diferencias → 1 ignorando esas dos
   claves. **Verificado en la app.**
3. El indicador de "ignorando" se ve en el icono y en el resumen. **Verificado** con capturas.
4. Los dos formatos salen pegables y con el resumen correcto. **Verificado** copiando de verdad
   al portapapeles desde la app.
5. Manual, pendiente: abrir el popover con el ratón y pegar el resultado en un ticket de verdad.
