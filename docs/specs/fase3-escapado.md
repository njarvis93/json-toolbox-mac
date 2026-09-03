# Spec: JSON ↔ string escapado

Lo principal de la Fase 3. `JSONEscaping` en JSONCore, menú **Convertir** en la app.

## Comportamiento esperado
- **Escapar como string** (⌃⌘E, modo editor): sustituye el contenido del editor por su literal
  de string JSON, con comillas incluidas. Va sobre el texto tal cual está — no reformatea antes,
  ni exige que sea JSON válido: escapar un fragmento roto para pegarlo en un ticket es un uso
  legítimo.
- **Desescapar string** (⌃⌘U, modo editor): la operación inversa.
- El resultado de escapar **sigue siendo un documento JSON válido** (una cadena en la raíz), así
  que la barra de estado se queda en verde y se puede formatear, guardar o volver a desescapar
  sin salir del editor. Ese es el motivo de hacerlo en el editor y no en el portapapeles, al
  revés que el XML (ver `fase3-xml.md`).
- Ambas acciones pasan por el mismo camino que Formatear (`model.text = …`), así que ⌘Z las
  deshace igual.

## Alcance
- No toca el parser ni el árbol: es una transformación de texto encima del formateador. Los
  literales numéricos sobreviven porque nadie los reinterpreta (`7.50` sigue siendo `7.50`).
- Escapar reusa `JSONFormatter.escape`: comilla, barra, `\n`, `\r`, `\t` y `\u00XX` para el resto
  de caracteres de control.
- Desescapar acepta **las dos formas** que aparecen en la práctica: el literal completo
  (`"{\"a\":1}"`) y el cuerpo suelto sin comillas (`{\"a\":1}`), que es lo que queda al copiar de
  un log o de un fuente Java/Swift.

## Casos límite
- `"a": "b"` empieza y acaba por comilla sin ser un literal. No se le quitan las comillas
  exteriores: solo se quitan si el interior no tiene ninguna comilla sin escapar.
- Escape desconocido (`\q`), `\u` truncado o con dígitos no hexadecimales → error con línea y
  columna del escape, contando líneas del texto de entrada (no del resultado).
- Pares suplentes: `😀` vuelve a ser 😀. Un suplente alto suelto se convierte en U+FFFD,
  igual que hace el parser, en vez de fallar.
- Entrada vacía o solo espacios → error "No hay nada que desescapar".
- El desescapado duplica en parte a `JSONString.unescape` (parser). Es a propósito: aquél trabaja
  sobre bytes de un token ya validado por el léxico y no necesita reportar posiciones; aquí la
  entrada es texto arbitrario pegado por el usuario y hace falta decir dónde está el fallo.

## Criterio de aceptación
1. `swift build` y `swift test` en verde. **Hecho** (73/73 el 2026-09-02, 12 de ellos de escapado).
2. El menú **Convertir** aparece en la barra de menús. **Verificado** con captura de pantalla real.
3. Manual: ⌃⌘E → el editor muestra el literal escapado y la barra sigue diciendo "JSON válido";
   ⌃⌘U → vuelve el original. **Confirmado por el usuario el 2026-09-02.**
4. Manual, pendiente de una pasada específica: pegar un string escapado copiado de un log (sin
   comillas exteriores) y ⌃⌘U → sale el JSON legible.
