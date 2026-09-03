# Estructura de archivos de la app (2026-09-02)

Petición del usuario: los 14 archivos de la app estaban en **una carpeta plana**, sin nada que
dijera qué era cada cosa. Van por capa:

```
JsonToolingApp/
├── App/
│   ├── JsonToolingApp.swift     @main, escenas y ventanas
│   ├── AppDelegate.swift        activación, archivos del Finder, aviso al cerrar
│   └── Commands.swift           los cinco grupos de menú
├── ViewModels/
│   ├── AppModel.swift           pantalla, barra de estado, las costuras
│   ├── DocumentModel.swift
│   ├── ComparisonModel.swift
│   ├── NavigationModel.swift
│   └── Preferences.swift
├── Views/
│   ├── ContentView.swift        ventana y toolbar
│   ├── StatusBar.swift
│   ├── ShortcutsWindow.swift
│   ├── Editor/                  EditorScreen, TreePanel
│   ├── Compare/                 CompareScreen, IgnoredKeysButton
│   └── AppKit/                  JSONTextView, VisualEffect
├── Support/                     Theme, FileImport
└── Resources/                   Assets.xcassets, Info.plist
```

## Por qué no hay `Models/`, `Services/` ni `Providers/`

Es MVVM, y **el modelo es `JSONCore`**: el parser, el formateador, el diff, el árbol y las
consultas viven en un paquete aparte que no sabe que existe una interfaz. Los cinco objetos de
`ViewModels/` son exactamente eso — estado de interfaz encima de ese modelo. Una carpeta `Models/`
dentro de la app estaría vacía o, peor, invitaría a meter ahí lógica que pertenece al paquete.

`Services/` y `Providers/` se descartaron a conciencia, aunque el usuario los había pedido por
nombre: esta app no tiene red, ni base de datos, ni inyección de dependencias. Lo único parecido a
un servicio es `FileImport` (disco y portapapeles, con el límite de 10 MB y sus mensajes), y una
carpeta `Services/` con un solo archivo dentro dice menos que `Support/`. Si algún día entra algo
de red, el sitio ya está claro.

## Lo que se partió de paso

- `JsonToolingApp.swift` tenía **ocho tipos** (la `App`, el `AppDelegate`, los cinco grupos de menú
  y `ShortcutsMenuItem`) → tres archivos.
- `ContentView.swift` tenía tres (`ContentView`, `IgnoredKeysButton`, `StatusBar`) → tres archivos,
  y `IgnoredKeysButton` se fue a `Views/Compare/`, que es donde se usa.
- `FileImport` salió de `DocumentModel.swift` a `Support/`: lo usan el documento y la comparación.

Lo que ya era coherente se quedó junto — `JSONTextView` con su gutter y su coordinador, por
ejemplo: son una sola pieza de TextKit y separarlos solo repartiría el mismo problema.

## Lo único que hubo que tocar del proyecto

Las carpetas del target están **sincronizadas con el disco**
(`PBXFileSystemSynchronizedRootGroup`, Xcode 16+), así que mover archivos no toca el `.pbxproj`.
La excepción es el `Info.plist`, que se referencia por ruta: `INFOPLIST_FILE` pasó a
`JsonToolingApp/Resources/Info.plist`.

Verificado además de compilar: los tipos de documento (`public.json`, `LSHandlerRank = Alternate`)
y el icono siguen llegando al bundle construido, y la app se abrió y se capturó igual que antes.
33 tests de app y 168 de `JSONCore` en verde.
