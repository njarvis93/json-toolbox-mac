# Spec: consultas JSONPath

Último trozo de la Fase 4. `JSONPath` en JSONCore, enchufado al buscador que ya existía.

## Alcance del subconjunto

Escrito a mano sobre el árbol, como decía el plan: JSONPath completo (expresiones de script,
uniones, rebanadas con paso) es mucho más de lo que hace falta para inspeccionar un documento y no
justifica una dependencia. Lo que se admite:

| | |
|---|---|
| `$` | la raíz |
| `.clave` / `['clave']` | un hijo; la forma con corchetes vale para claves con puntos o espacios |
| `[2]` / `[-1]` | un elemento del array; los negativos cuentan desde el final |
| `.*` / `[*]` | todos los hijos |
| `..clave` | esa clave a cualquier profundidad |
| `..*` | todos los descendientes |
| `[?(@.clave)]` | los hijos que tengan esa clave |
| `[?(@.clave > 10)]` | ídem comparando: `==`, `!=`, `<`, `<=`, `>`, `>=` |

Los valores de un filtro pueden ser número, cadena entre comillas simples o dobles, `true`,
`false` o `null`.

Dos límites que salieron en la pasada manual del usuario (2026-09-02) y que conviene tener
escritos, porque el segundo despista:

- `[?(@.cliente.vip == true)]` — **ruta anidada dentro de un filtro, no admitida**. Un filtro mira
  una clave directa del hijo. Se responde con "Consulta no válida" y la columna del error, que es
  lo correcto.
- `$..cliente[?(@.vip == true)]` — **0 coincidencias, y sin error**. Filtrar recorre los hijos del
  nodo, y los hijos de `cliente` son escalares que no tienen `vip`. Es consistente con la regla
  ("los hijos que tengan esa clave"), pero leído deprisa parece que debería devolver el cliente.
  Lo que se quiere ahí es `$.tienda.pedidos[?(@.vip == true)]` sobre el array, o `$..vip`.

Los dos se dejan como están: el subconjunto es deliberadamente pequeño y el error del primero es
claro. Si en uso real estorban, el primero es el que vale la pena subir.

**Va sobre `JSONNode`, no sobre `JSONValue`**, por lo mismo que el resto de la fase: el resultado
tiene que poder señalarse en el editor. Una consulta que devuelve valores sueltos, sin posición,
no sirve para navegar — hay un test que comprueba que el rango de `$.lineas[0].precio` recorta
exactamente `42.90` sobre el texto.

## Decisiones

- **Los números se comparan como números.** `[?(@.n > 9)]` no puede quedarse con `10` por ser
  "10" < "9" en texto. Las cadenas se comparan alfabéticamente.
- **Comparar tipos distintos no es un error**: `[?(@.sku > 10)]` sobre una cadena sencillamente no
  cumple. Fallar ahí obligaría a saber el tipo antes de preguntar.
- **`..` devuelve en orden de documento.** Se mira cada nodo del recorrido en preorden, no los
  hijos de cada nodo: recogiendo hijos, `$..x` sobre `{"a":{"x":1},"x":2}` devolvía la `x` de
  arriba antes que la de dentro de `a`.
- **Los duplicados se quitan** conservando el orden: `..` puede llegar al mismo nodo por dos
  caminos.
- Los errores son `JSONError` con la **columna dentro de la consulta**, para poder señalar dónde
  está el fallo.

## En la app

No hay campo nuevo: **el ámbito del buscador gana una opción, "Ruta"**. Así la consulta reutiliza
todo lo que ya había — recuento, ⌘G / ⇧⌘G para saltar entre resultados, árbol filtrado a las
coincidencias y sus ancestros, y selección en el editor al saltar. Internamente `JSONSearch.find`
delega en `JSONPath` para decidir quién coincide y sigue con el mismo recorrido, así que los
ancestros y el orden de documento salen iguales para los dos casos.

Una consulta mal escrita no es una búsqueda vacía: la barra dice **"Consulta no válida"** en
naranja —corto, para que no se trunque en un panel de 260 pt— y el cuerpo del panel enseña el
mensaje completo con su columna. `"precio"` a secas, con el ámbito Ruta, es un error y no una
búsqueda de texto disfrazada.

## El ámbito manda, pero se avisa

Probándolo el usuario, el fallo real: escribes `$..precio` con el ámbito en "Todo" —que es el de
salida—, se busca como **texto literal**, no aparece, y la app se limitaba a decir "Sin
coincidencias" sin dar ninguna pista. Parecía que las consultas no funcionaban.

No se cambia el ámbito solo: buscar un `$` de verdad (en precios, por ejemplo) es legítimo, y
adivinar la intención se equivocaría alguna vez. Cuando la consulta empieza por `$`, el ámbito
busca texto y no hay ninguna coincidencia, el cuerpo del panel lo dice y ofrece **"Buscar como
ruta"**, que cambia el ámbito en un clic.

## Casos límite
- Índice fuera de rango o clave inexistente: cero resultados, sin error.
- Filtro sobre una clave que no existe: no cumple.
- Consulta a medio escribir (`$.` mientras se teclea): sale como consulta no válida. Es honesto,
  aunque parpadee mientras se escribe.

## Criterio de aceptación
1. `swift build` y `swift test` en verde. **Hecho**: 130/130 el 2026-09-02, 25 de ellos de rutas.
2. `$.lineas[?(@.precio > 10)]` en el documento de ejemplo: ámbito "Ruta", "1 coincidencia", árbol
   filtrado a `$ → lineas → 0`. **Verificado** con captura de la ventana real, CPU al 0 %.
3. `$.lineas[?(@.precio ~ 10)]`: "Consulta no válida" en la barra y el mensaje completo con la
   columna 21 en el cuerpo. **Verificado** con captura.
4. `$..precio` con el ámbito "Todo": el panel avisa de que parece una ruta y el botón "Buscar
   como ruta" lo cambia y saca las 2 coincidencias. **Verificado** tecleando de verdad (eventos
   de teclado dentro del proceso) y con captura.
5. Manual, pendiente: saltar entre resultados con ⌘G sobre una consulta de ruta.
