# JsonTooling

App nativa de macOS para **leer, validar, formatear, convertir, navegar y comparar JSON**.
Swift + SwiftUI, sin dependencias externas, sin Electron.

![CI](https://github.com/njarvis93/json-toolbox-mac/actions/workflows/ci.yml/badge.svg)

## Qué hace

- **Editor** con validación en vivo, error con línea y columna, y la línea mala en rojo.
- **Formatear, minificar y ordenar claves**, con sangría de 2, 4 o tabulador.
- **Panel de estructura** sincronizado con el texto en los dos sentidos, con búsqueda por clave
  o por valor y consultas de ruta (`$.a.b[0]`, `..clave`, `[?(@.precio > 40)]`).
- **Comparar** dos documentos: diferencia estructural, no textual, con las diferencias en una
  tabla que salta a la línea, claves ignorables y exportación a texto o Markdown.
- **Convertir**: a string escapado y de vuelta, y a XML y de vuelta.

## Instalar

Descarga el `.zip` de la última [release](https://github.com/njarvis93/json-toolbox-mac/releases)
y arrastra la app a Aplicaciones. Va firmada ad-hoc pero **sin notarizar**, así que la primera vez
hay que abrirla con clic derecho → Abrir, o quitarle la cuarentena:

```sh
xattr -dr com.apple.quarantine /Applications/JsonTooling.app
```

Requiere **macOS 14 o superior**.

## Compilar y probar

```sh
swift test                                    # 168 tests de JSONCore, menos de un segundo
./Scripts/coverage.sh 80                      # cobertura de JSONCore (91,83 % hoy)
./Scripts/format.sh                           # aplica el formato del proyecto
./Scripts/package.sh                          # .app universal firmada ad-hoc en build/
```

La app se compila con Xcode, que consume el paquete como dependencia local:

```sh
xcodebuild -project JsonToolingApp/JsonToolingApp.xcodeproj \
           -scheme JsonToolingApp -destination 'platform=macOS' test
```

## Atajos

| | |
|---|---|
| ⇧⌘F | Formatear |
| ⌘S / ⇧⌘S | Guardar / Guardar como |
| ⌘L | Ir a línea |
| ⌘F | Buscar en la estructura |
| ⌘G / ⇧⌘G | Coincidencia o diferencia siguiente / anterior |
| ⌃⌘S | Mostrar u ocultar la estructura |
| ⌃⌘E / ⌃⌘U | Escapar como string / desescapar |
| ⌘/ | Ver todos los atajos |

## Cómo está organizado

```
Sources/JSONCore/          El motor: lexer, parser, formateador, diff, árbol, búsqueda,
                           consultas, escapado y XML. Sin AppKit — todo testeable.
Tests/JSONCoreTests/       168 tests.
JsonToolingApp/
├── JsonToolingApp/
│   ├── App/               Arranque, escenas, AppDelegate y los grupos de menú.
│   ├── ViewModels/        AppModel, DocumentModel, ComparisonModel, NavigationModel,
│   │                      Preferences.
│   ├── Views/             ContentView, StatusBar + Editor/, Compare/, AppKit/.
│   ├── Support/           Theme, FileImport.
│   └── Resources/         Assets.xcassets, Info.plist.
└── JsonToolingAppTests/   33 tests de la capa de app.
Ejemplos/                  Datos para probar a mano XML, consultas y comparación.
docs/PLAN.md               El plan por fases.
docs/specs/                Un archivo por decisión, con el porqué y lo que se descartó.
```

Es MVVM, y **el modelo es `JSONCore`**: vive en su propio paquete y no sabe que existe una
interfaz. Por eso `swift test` corre sin abrir Xcode.

## Las tres decisiones que sostienen el motor

Si alguna vez parece que esto se simplificaría con `JSONSerialization` o `Codable`, es que se ha
perdido el motivo:

**1 · Parser propio con posiciones.** `JSONParser.validate` devuelve mensaje, línea y columna, con
la columna en caracteres y no en bytes, así que `"añ"` no descuadra nada. Los errores del runtime
no dan una posición que sirva para pintar la línea en rojo.

**2 · Ningún número pasa por `Double`.** `JSONValue.number(raw: String)` guarda el literal y el
formateador reemite los tokens originales. Un round-trip por `Double` degrada
`90071992547409931` (mayor que 2^53) y normaliza `7.50` a `7.5`. Hay tests que fijan las dos cosas.

**3 · El diff es estructural.** `JSONDiff.compare` recorre árboles y devuelve rutas
(`lineas[0].cantidad`). Reordenar claves, cambiar el espaciado o escribir `1.50` en vez de `1.5`
no son diferencias. Los elementos de un array se emparejan **por clave de identidad** cuando la
hay: insertar uno al principio deja de marcar el array entero.

Decisión discutible, tomada a conciencia: **las claves duplicadas se rechazan como error**. El
estándar las deja indefinidas y otras herramientas se quedan con la última; para una herramienta
de inspección es más útil verlas.

## Calidad

`ci.yml` es una **cadena**, no cuatro comprobaciones sueltas: cada eslabón solo arranca si el
anterior pasó, así que la señal llega en orden de fundamento y no se gastan minutos compilando y
analizando algo que ya se sabe roto.

| | Qué hace |
|---|---|
| **1 · Tests** | 168 de `JSONCore` y 33 de la capa de app. Calcula el informe de cobertura. |
| **2 · Calidad** | Cobertura de `JSONCore` ≥ 80 %, formato con `swift-format`, compilar sin un solo aviso, y CodeQL. |
| **3 · Build** | La `.app` universal en Release, comprobando que el bundle lleva el icono y la asociación con `.json`. |

`release.yml` va aparte porque lo dispara un tag `vX.Y.Z`, no un push: compila, empaqueta y
publica la `.app` en una Release.

**CodeQL solo corre si el repositorio es público.** El análisis de código es gratis ahí, pero en
uno privado necesita GitHub Advanced Security, que es de pago: el análisis funciona y lo que falla
es publicar los resultados. El paso se queda escrito y condicionado, así que empieza a funcionar
solo el día que el repositorio se haga público.

La cobertura de la capa de app se publica en el resumen de cada ejecución pero **no bloquea**:
más de la mitad de ese target son vistas de SwiftUI y paneles de AppKit que no se pueden ejecutar
sin interfaz, así que un umbral ahí mediría lo que no importa. La puerta está donde vive la lógica
que puede romperse en silencio.

## Alcance

Dentro: lo de la lista de arriba. Fuera de la v1: conversión a YAML y CSV, generación de tipos, y
documentos por encima de 10 MB — por encima se rechaza la importación en vez de congelar la
ventana, y el resaltado se apaga por encima de 512 KB. Ver [docs/PLAN.md](docs/PLAN.md).

## Licencia

Código **visible, no abierto**: [PolyForm Noncommercial 1.0.0](LICENSE). Puedes leerlo,
compilarlo y usarlo para cualquier fin no comercial. El uso comercial requiere una licencia
aparte — abre una issue para pedirla.

El proyecto se desarrolló en privado bajo MIT hasta el 2026-09-03, pero ninguna de esas versiones
se distribuyó: este repositorio empieza en el commit inicial, ya bajo PolyForm.
