import Foundation

/// Árbol paralelo al de `JSONValue`, con la posición de cada valor en el texto.
///
/// El plan dejaba elegir entre meter el rango dentro de `JSONValue` o llevar un árbol
/// aparte. Va aparte a propósito: `JSONValue` se compara por valor en `JSONDiff`, y dos
/// documentos equivalentes escritos con distinto espaciado **tienen que seguir siendo
/// iguales**. Si el rango viviera dentro del valor, o contaminaría la igualdad o habría que
/// acordarse de excluirlo en cada sitio. Aquí la separación es la que ya existe entre "qué
/// dice el documento" (`JSONValue`) y "dónde lo dice" (`JSONNode`).
///
/// Los desplazamientos son **UTF-16**, que es lo que usan `NSTextView` y
/// `NSAttributedString`: con bytes UTF-8 la selección se descuadra en cuanto hay un emoji.
public struct JSONNode: Equatable, Identifiable {

    public enum Kind: String, Equatable {
        case object, array, string, number, bool, null
    }

    public let kind: Kind
    /// Clave dentro del objeto padre. `nil` en la raíz y en los elementos de un array.
    public let key: String?
    /// Ruta con el mismo formato que `JSONChange.path`: `lineas[0].cantidad`, raíz `$`.
    public let path: String
    /// Rango del valor en unidades UTF-16.
    public let start: Int
    public let end: Int
    /// Inicio contando la clave, para poder seleccionar `"clave": valor` entero.
    /// Igual que `start` cuando el nodo no tiene clave.
    public let startWithKey: Int
    /// Línea (1-based) donde empieza el valor.
    public let line: Int
    /// Literal del escalar tal cual aparece (números y booleanos) o el valor ya desescapado
    /// de la cadena. `nil` en objetos y arrays.
    public let scalarText: String?
    public let children: [JSONNode]

    /// La ruta identifica al nodo: el parser rechaza las claves duplicadas, así que dentro de
    /// un documento válido no hay dos iguales.
    public var id: String { path }

    public var typeName: String { kind.rawValue }

    /// Hijos para `OutlineGroup`/listas jerárquicas: `nil` en las hojas, para que no les
    /// salga triángulo de desplegar.
    public var branch: [JSONNode]? { children.isEmpty ? nil : children }

    public var isContainer: Bool { kind == .object || kind == .array }

    /// Etiqueta del nodo en el árbol: la clave, el índice, o la raíz.
    public var label: String {
        if let key { return key }
        if path == "$" { return "$" }
        guard let open = path.lastIndex(of: "["), path.hasSuffix("]") else { return path }
        return String(path[path.index(after: open)..<path.index(before: path.endIndex)])
    }

    /// Resumen para pintar a la derecha de la etiqueta.
    public var summary: String {
        switch kind {
        case .object:
            return children.isEmpty
                ? "{}" : "{ \(children.count) \(children.count == 1 ? "clave" : "claves") }"
        case .array:
            return children.isEmpty
                ? "[]" : "[ \(children.count) \(children.count == 1 ? "elemento" : "elementos") ]"
        case .string:
            return "\"\(scalarText ?? "")\""
        default:
            return scalarText ?? ""
        }
    }

    /// Nodo más profundo que contiene ese desplazamiento UTF-16, para ir de texto a árbol.
    /// El rango se toma cerrado por la derecha: con el cursor justo al final de un valor
    /// sigue siendo ese valor el que interesa resaltar.
    public func node(atUTF16 offset: Int) -> JSONNode? {
        guard offset >= startWithKey, offset <= end else { return nil }
        for child in children {
            if let hit = child.node(atUTF16: offset) { return hit }
        }
        return self
    }

    /// Cadena desde la raíz hasta el nodo más profundo que contiene ese desplazamiento.
    /// Es lo que hace falta para desplegar el árbol hasta donde está el cursor.
    public func chain(atUTF16 offset: Int) -> [JSONNode] {
        guard offset >= startWithKey, offset <= end else { return [] }
        for child in children {
            let deeper = child.chain(atUTF16: offset)
            if !deeper.isEmpty { return [self] + deeper }
        }
        return [self]
    }

    /// Igual que `chain(atUTF16:)`, pero teniendo en cuenta la línea del cursor.
    ///
    /// Con el cursor al principio de una línea, el desplazamiento cae en la sangría — que
    /// pertenece al contenedor, no al valor escrito ahí — y señalar el contenedor no es lo
    /// que espera nadie. Si hay un hijo que empieza en esa misma línea, más adelante, se baja
    /// **un solo nivel** hasta él. Solo uno: en `"cliente": { "id": 1, … }`, todo en la misma
    /// línea, bajar sin freno acabaría señalando `cliente.id` en vez de `cliente`.
    ///
    /// No se baja cuando el desplazamiento es justo el principio del contenedor: ahí el
    /// cursor está señalando el contenedor a propósito (es lo que hace "revelar" desde el
    /// árbol) y moverlo sería pelearse con el usuario.
    public func chain(atUTF16 offset: Int, line: Int) -> [JSONNode] {
        var chain = self.chain(atUTF16: offset)
        guard let last = chain.last, last.isContainer,
            offset != last.start, offset != last.startWithKey,
            let child = last.children.first(where: { $0.line == line && $0.startWithKey >= offset })
        else { return chain }
        chain.append(child)
        return chain
    }

    public func node(withPath path: String) -> JSONNode? {
        if self.path == path { return self }
        for child in children {
            if let hit = child.node(withPath: path) { return hit }
        }
        return nil
    }

    /// Recorrido en preorden, que es el orden en que se ven las filas del árbol.
    public func forEachNode(_ body: (JSONNode) -> Void) {
        body(self)
        for child in children { child.forEachNode(body) }
    }
}
