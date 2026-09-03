# Spec: JSON ↔ XML

Segunda prioridad de la Fase 3. `JSONXML` en JSONCore, menú **Convertir** en la app.

## La decisión que el plan dejaba abierta

El plan decía "puede bastar una sola dirección para empezar; decidir alcance al llegar". Se hacen
**las dos**, pero la vuelta solo es exacta sobre XML que siga la convención de ida. Esa convención
es lo que hace que el viaje de ida y vuelta no pierda nada:

- Cada clave de un objeto es un elemento con ese nombre.
- Un array es un elemento con `type="array"` y un hijo `<item>` por elemento.
- Los valores que no son cadenas llevan `type` (`number`, `bool`, `null`, `object`, `array`);
  las cadenas no llevan nada, que es el caso común y el que más ensuciaría.
- Los números viajan como su literal original: `7.50` no se normaliza y `90071992547409931` no
  pierde precisión. Al volver se revalidan con el mismo léxico que el parser.
- Una clave que no sea un nombre XML válido (espacios, empezar por dígito, prefijo `xml`) se emite
  como `<entry key="la clave">`.
- Contenedores vacíos: `<a type="array"/>`, `<b type="object"/>`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<pedido type="object">
  <pedidoId>4471-AC</pedidoId>
  <cliente type="object">
    <id type="number">90071992547409931</id>
  </cliente>
  <lineas type="array">
    <item type="object">…</item>
  </lineas>
  <transportista type="null"/>
</pedido>
```

Al leer XML **escrito a mano**, sin `type`, se infiere por la forma: un elemento con hijos es un
objeto, o un array si todos sus hijos se llaman `item`; uno sin hijos es una cadena. Claves
repetidas (`<tag>a</tag><tag>b</tag>`, la forma habitual de escribir listas a mano) se agrupan en
un array. Sin `type`, `41` llega como `"41"` y no como número: el XML no distingue, y adivinar
sería peor que decirlo.

## Dónde vive el resultado

**"Copiar como XML" deja el XML en el portapapeles; no lo mete en el editor.** El editor es de
JSON: valida, resalta y numera JSON. Dejarle dentro un documento XML lo pondría en rojo, con el
resaltado sin sentido y con el riesgo de guardarlo encima del `.json` abierto. **"Pegar desde
XML"** hace el camino contrario: lee el portapapeles, convierte y deja el JSON formateado en el
editor (como cualquier otra importación: se olvida el `fileURL`, así que ⌘S pregunta destino).

El nombre del elemento raíz sale del nombre del documento (`pedido-4471.json` → `<pedido-4471>`);
si no es un nombre XML válido, `<root>`.

## Casos límite
- XML mal formado, `type` desconocido, `type="number"` con un valor que no es un número o
  `type="bool"` que no es `true`/`false` → error con la línea que da `XMLParser`, mostrado en la
  barra de estado vía `flash(...)`; el editor no se toca.
- `&`, `<`, `>` se escapan en el texto; además `"` y saltos de línea en los atributos `key`.
- El portapapeles se somete al mismo límite de 10 MB que la importación de archivos.
- Namespaces, atributos ajenos a `type`/`key`, comentarios, CDATA y texto mixto: **fuera de
  alcance**. Los atributos desconocidos se ignoran; el texto mixto se pierde (se queda con los
  hijos y descarta el texto suelto).

## Criterio de aceptación
1. `swift build` y `swift test` en verde. **Hecho** (73/73 el 2026-09-02, 17 de ellos de XML,
   incluida la ida y vuelta del documento de ejemplo completo).
2. El menú **Convertir** aparece en la barra de menús. **Verificado** con captura real.
3. Manual, pendiente (sin permiso de Accessibility para automatizar el ratón en este entorno):
   Convertir → Copiar como XML, pegar en un editor de texto y comprobar el resultado; volver con
   Pegar desde XML y comprobar que sale el JSON de partida.
