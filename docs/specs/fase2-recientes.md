# Spec: menú "Abrir reciente"

## Comportamiento esperado
El menú Archivo gana un submenú "Abrir reciente" con un ítem por cada URL en
`model.recentDocuments` (más reciente primero), cada uno cargando ese archivo en el editor al
pulsarlo. Si la lista no está vacía, un separador y "Vaciar menú" al final.

## Casos límite
- Lista vacía: el submenú existe pero sin ítems de archivo ni "Vaciar menú".
- Un archivo movido/borrado del disco tras aparecer en recientes: al pulsarlo, `load` ya maneja el
  fallo de lectura con el `flash(...)` existente — no hace falta manejo especial aquí.

## Criterio de aceptación
1. `swift build` sin errores.
2. Manual: abrir dos `.json` distintos → ambos aparecen en "Abrir reciente", el último arriba;
   "Vaciar menú" los quita a todos.

**Verificado a mano por el usuario el 2026-09-02.**
