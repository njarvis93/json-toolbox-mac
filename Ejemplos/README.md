# Datos para las pasadas manuales pendientes

Lo que el plan da por bueno sin que lo hayas probado en uso real: **XML**, **consultas de ruta** y
**comparar dos respuestas de API**. Cada cifra de aquí abajo está comprobada ejecutando el motor
sobre estos mismos archivos, así que si la app te da otra cosa, es un fallo de la app.

---

## 1 · XML, las dos direcciones

### Ida y vuelta sin pérdida — `xml-ida-y-vuelta.json`

Ábrelo, **Convertir → Copiar como XML**, pega el XML en cualquier editor para verlo, y luego
**Convertir → Pegar desde XML** de vuelta en la app.

Tiene dentro justo lo que suele romperse: un entero mayor que 2^53, `7.50` con cero final,
notación exponencial, `null`, booleanos, cadena vacía, acentos, un emoji, comillas y barras
invertidas, un salto de línea, objeto y array vacíos, y **dos claves que no son nombres XML
válidos** (`clave con espacios` y `1_empieza_por_digito`).

Comprobado: la vuelta da un documento **idéntico** al original, con `7.50` y
`90071992547409931` intactos. Así empieza el XML que debe salir:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<pedido type="object">
  <pedidoId>4471-AC</pedidoId>
  <entero_grande type="number">90071992547409931</entero_grande>
  <decimal_con_cero type="number">7.50</decimal_con_cero>
```

Lo que hay que mirar a ojo: que las dos claves inválidas salgan como `<entry key="…">` y que el
emoji y los acentos vuelvan enteros.

### Pegar XML anotado — `xml-anotado-para-pegar.xml`

Cópialo entero y **Convertir → Pegar desde XML**. Los tipos van declarados, así que
`intentos` debe llegar como número `3`, `reintentable` como `false`, `transportista` como `null`,
y `lineas` como array de dos objetos.

### Pegar XML de otro sitio — `xml-escrito-a-mano.xml`

El caso real: un XML que no ha salido de esta app, sin `type=`. Aquí la forma se **infiere**, y
sus escalares llegan como **cadenas** — `"cantidad": "2"`, no `2`. Es lo esperado, no un fallo.
Los dos `<linea>` repetidos deben convertirse en un array.

---

## 2 · Consultas de ruta — `consultas.json`

Panel de estructura (⌃⌘S) → ámbito **Ruta**. Escribe cada consulta y compara el recuento:

| Consulta | Coincidencias |
|---|---|
| `$.tienda.pedidos[0].id` | 1 |
| `$..sku` | 6 |
| `$.tienda.pedidos[-1].estado` | 1 |
| `$.tienda.almacenes[*].ciudad` | 3 |
| `$.tienda.pedidos[*].cliente.*` | 9 |
| `$..vip` | 3 |
| `$..stock.*` | 5 |
| `$.tienda.almacenes[1].stock` | 1 |
| `$..lineas[?(@.precio > 40)]` | 3 |
| `$..lineas[?(@.cantidad >= 2)]` | 3 |
| `$.tienda.pedidos[?(@.estado == "CANCELADO")]` | 1 |
| `$..pedidos[?(@.estado != "CANCELADO")]` | 2 |

Y dos que **no** están en el subconjunto, para que veas cómo lo dice:

- `$.tienda.pedidos[?(@.cliente.vip == true)]` → "Consulta no válida". Un filtro solo mira **una
  clave directa**, no una ruta anidada. Está declarado así en `docs/specs/fase4-jsonpath.md`.
- `$..cliente[?(@.vip == true)]` → 0 coincidencias, sin error. Filtrar recorre los hijos, y los
  hijos de `cliente` son escalares que no tienen `vip`. Consistente, aunque despista.

Si alguna de las dos te parece que debería funcionar, dilo y lo subimos al subconjunto.

Prueba también el aviso del ámbito: escribe `$..sku` con el ámbito en **Todo** — debe decir
"Sin coincidencias" y ofrecerte "Buscar como ruta" en un clic.

---

## 3 · Comparar dos respuestas — `api-respuesta-A.json` y `api-respuesta-B.json`

Pantalla **Comparar**, A en la izquierda y B en la derecha. Son la misma respuesta de API antes y
después de que el pedido se envíe, con el ruido que traen las respuestas de verdad: el bloque
`meta` cambia entero en cada llamada, B viene con **las claves en otro orden**, y sus precios
están escritos distinto (`89.0` en vez de `89.00`, `42.900`, `7.5`, `4.950`).

**Sin ignorar nada: 12 diferencias.** Con las tres claves de `meta` ignoradas
(`requestId, generadoEn, duracionMs` en el botón del ojo): **9**.

Lo que tiene que aparecer en esas 9:

```
modificado  pedido.estado                 EN_PREPARACION → ENVIADO
modificado  pedido.envio.metodo           estandar → express
modificado  pedido.envio.transportista    null → "SEUR"
añadido     pedido.envio.seguimiento
movido      pedido.lineas[2]
añadido     pedido.lineas[0]
modificado  pedido.totales.{subtotal,impuestos,total}
```

Lo importante está en las dos líneas de `lineas`. B mete una línea nueva **al principio** y
reordena las demás, y aun así salen **dos** diferencias y no cinco: los elementos se emparejan por
`sku` y no por posición. Y ninguna de las tres formas distintas de escribir los precios cuenta
como diferencia — eso es lo que hace que el diff sea estructural y no textual.

Cosas que probar encima de eso:

- Clic en una fila de la tabla → debe saltar y resaltar esa línea en las dos columnas.
- ⌘G / ⇧⌘G para recorrer las 9 y volver al principio.
- **Exportar diferencias** en los dos formatos: el volcado tiene que decir que se están ignorando
  3 claves. Si no lo dice, es un fallo — una comparación que esconde cosas tiene que confesarlo.
- Vista **Entradas** y Formatear cada lado desde su cabecera: B viene con las claves desordenadas,
  y ordenarlas no debe cambiar el número de diferencias.
