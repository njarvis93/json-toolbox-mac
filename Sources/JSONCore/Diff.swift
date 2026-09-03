import Foundation

public struct JSONChange: Equatable {
    public enum Kind: String, Equatable {
        case added, removed, modified, moved

        /// Para la etiqueta de una fila: "cambio **modificado**".
        public var label: String {
            switch self {
            case .added: return "añadido"
            case .removed: return "eliminado"
            case .modified: return "modificado"
            case .moved: return "movido"
            }
        }

        /// Para contar diferencias: "1 modificad**a**", "2 modificad**as**". Concuerda en
        /// género con "diferencia" y en número con la cuenta.
        public func counted(_ n: Int) -> String {
            let stem: String
            switch self {
            case .added: stem = "añadida"
            case .removed: stem = "eliminada"
            case .modified: stem = "modificada"
            case .moved: stem = "movida"
            }
            return "\(n) " + stem + (n == 1 ? "" : "s")
        }
    }
    /// Ruta tipo `lineas[1].cantidad`. La raíz es `$`.
    ///
    /// En los arrays emparejados por clave, la ruta es la del **elemento en A** (y la de B
    /// cuando solo existe en B). Un elemento que ha cambiado de sitio tiene dos rutas y aquí
    /// solo cabe una; la de A es la que sirve para localizarlo en la columna izquierda.
    public let path: String
    public let kind: Kind
    /// En un `.moved`, el índice de origen y el de destino en vez del valor: el valor es el
    /// mismo a los dos lados, y lo que interesa ver es de dónde a dónde se ha movido.
    public let before: JSONValue?
    public let after: JSONValue?
}

/// Cómo comparar. La lista de claves de identidad es lo que decide si un array se empareja por
/// clave o por posición.
public struct DiffOptions {
    /// Nombres candidatos a identificar un elemento de array, en orden de preferencia. Ser
    /// candidato no basta: la clave tiene que estar en **todos** los elementos de los dos
    /// arrays y no repetirse en ninguno de los dos (ver `JSONDiff.identityKey`).
    public var identityKeys: [String]

    /// Claves cuyas diferencias no se informan, **por nombre y a cualquier profundidad**:
    /// `requestId` se ignora esté donde esté. Es para los campos que cambian solos en cada
    /// respuesta —marcas de tiempo, identificadores de petición, versiones— y que tapan con
    /// ruido la diferencia que se está buscando.
    ///
    /// Por nombre y no por ruta completa a propósito: es lo cómodo, y quien necesite distinguir
    /// `meta.requestId` de `datos.requestId` es un caso bastante más raro. Si estorba, se
    /// añadirá la forma con ruta.
    public var ignoredKeys: Set<String>

    public static let commonIdentityKeys = [
        "id", "uuid", "guid", "_id", "key", "clave", "sku", "code", "codigo", "ref", "slug",
    ]

    /// Por encima de este número de elementos emparejados no se buscan reordenaciones: la
    /// detección es cuadrática y a partir de cierto tamaño no compensa.
    public static let maxMoveDetection = 500

    public init(
        identityKeys: [String] = DiffOptions.commonIdentityKeys,
        ignoredKeys: Set<String> = []
    ) {
        self.identityKeys = identityKeys
        self.ignoredKeys = ignoredKeys
    }

    /// Lee una lista escrita a mano: separada por comas o saltos de línea, sin espacios sueltos
    /// ni entradas vacías.
    public static func parseIgnoredKeys(_ text: String) -> Set<String> {
        Set(
            text.split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
    }
}

/// Diff estructural: compara árboles por ruta, no texto por texto.
/// Reordenar claves no genera diferencias; cambiar un valor sí.
public enum JSONDiff {

    public static func compare(
        _ a: JSONValue, _ b: JSONValue,
        options: DiffOptions = DiffOptions()
    ) -> [JSONChange] {
        var acc: [JSONChange] = []
        walk(a, b, path: "", into: &acc, options: options)
        return acc
    }

    public static func compare(
        _ a: String, _ b: String,
        options: DiffOptions = DiffOptions()
    ) throws -> [JSONChange] {
        compare(try JSONParser.parse(a).value, try JSONParser.parse(b).value, options: options)
    }

    private static func walk(
        _ a: JSONValue, _ b: JSONValue, path: String,
        into acc: inout [JSONChange], options: DiffOptions
    ) {
        let root = path.isEmpty ? "$" : path

        if a.typeName != b.typeName {
            acc.append(JSONChange(path: root, kind: .modified, before: a, after: b))
            return
        }

        switch (a, b) {
        case let (.object(oa), .object(ob)):
            var seen = Set<String>()
            for k in oa.keys {
                seen.insert(k)
                if options.ignoredKeys.contains(k) { continue }
                let p = path.isEmpty ? k : "\(path).\(k)"
                if let bv = ob[k] {
                    walk(oa[k]!, bv, path: p, into: &acc, options: options)
                } else {
                    acc.append(JSONChange(path: p, kind: .removed, before: oa[k], after: nil))
                }
            }
            for k in ob.keys where !seen.contains(k) && !options.ignoredKeys.contains(k) {
                let p = path.isEmpty ? k : "\(path).\(k)"
                acc.append(JSONChange(path: p, kind: .added, before: nil, after: ob[k]))
            }

        case let (.array(aa), .array(ab)):
            let base = path.isEmpty ? "$" : path
            // Con una clave de identidad se empareja por ella; si no, por posición, que es lo
            // que se hacía siempre y sigue siendo lo correcto para arrays de escalares.
            if let key = identityKey(aa, ab, options) {
                walkPaired(aa, ab, key: key, base: base, into: &acc, options: options)
            } else {
                for i in 0..<max(aa.count, ab.count) {
                    let p = "\(base)[\(i)]"
                    if i >= aa.count {
                        acc.append(JSONChange(path: p, kind: .added, before: nil, after: ab[i]))
                    } else if i >= ab.count {
                        acc.append(JSONChange(path: p, kind: .removed, before: aa[i], after: nil))
                    } else {
                        walk(aa[i], ab[i], path: p, into: &acc, options: options)
                    }
                }
            }

        default:
            if a != b {
                acc.append(JSONChange(path: root, kind: .modified, before: a, after: b))
            }
        }
    }

    // MARK: - Emparejar arrays por clave

    /// Primera clave candidata que de verdad identifica a los elementos de **los dos** arrays.
    ///
    /// No basta con que el nombre esté en la lista: tiene que estar presente en todos los
    /// elementos, tener valor escalar y no repetirse. Con eso, emparejar por ella es seguro; sin
    /// eso se compara por posición, que es lo que se hacía antes.
    static func identityKey(_ a: [JSONValue], _ b: [JSONValue], _ options: DiffOptions) -> String? {
        guard !a.isEmpty, !b.isEmpty else { return nil }
        return options.identityKeys.first { identifies($0, a) && identifies($0, b) }
    }

    private static func identifies(_ key: String, _ items: [JSONValue]) -> Bool {
        var seen = Set<String>()
        for item in items {
            guard case .object(let object) = item,
                let value = object[key],
                let token = identityToken(value),
                seen.insert(token).inserted
            else { return false }
        }
        return true
    }

    /// Los números se comparan por su literal y no como `Double`: un identificador de más de
    /// 2^53 no puede pasar por `Double` sin arriesgarse a confundir dos elementos distintos.
    private static func identityToken(_ value: JSONValue) -> String? {
        switch value {
        case .string(let s): return "s:" + s
        case .number(let raw): return "n:" + raw
        case .bool(let b): return "b:\(b)"
        case .null, .object, .array: return nil
        }
    }

    private static func token(_ item: JSONValue, _ key: String) -> String? {
        guard case .object(let object) = item, let value = object[key] else { return nil }
        return identityToken(value)
    }

    private static func walkPaired(
        _ a: [JSONValue], _ b: [JSONValue], key: String, base: String,
        into acc: inout [JSONChange], options: DiffOptions
    ) {
        var indexInB: [String: Int] = [:]
        for (j, item) in b.enumerated() {
            if let t = token(item, key) { indexInB[t] = j }
        }

        var pairs: [(a: Int, b: Int)] = []
        var matchedInB = Set<Int>()
        var removed: [Int] = []
        for (i, item) in a.enumerated() {
            guard let t = token(item, key), let j = indexInB[t] else { removed.append(i); continue }
            pairs.append((i, j))
            matchedInB.insert(j)
        }

        let movedFromA = movedIndices(pairs)

        for (i, j) in pairs {
            let path = "\(base)[\(i)]"
            if movedFromA.contains(i) {
                acc.append(
                    JSONChange(
                        path: path, kind: .moved,
                        before: .number(raw: "\(i)"), after: .number(raw: "\(j)")))
            }
            walk(a[i], b[j], path: path, into: &acc, options: options)
        }
        for i in removed {
            acc.append(JSONChange(path: "\(base)[\(i)]", kind: .removed, before: a[i], after: nil))
        }
        for (j, item) in b.enumerated() where !matchedInB.contains(j) {
            acc.append(JSONChange(path: "\(base)[\(j)]", kind: .added, before: nil, after: item))
        }
    }

    /// Cuáles de los elementos emparejados han cambiado **de orden relativo**, no de índice.
    ///
    /// Es la diferencia entre que la funcionalidad sirva o no: insertar un elemento al principio
    /// desplaza el índice de todos los demás, y marcarlos a todos como movidos sería exactamente
    /// el ruido que se venía a quitar. Los que están en la subsecuencia común más larga de los
    /// dos órdenes se consideran quietos; los demás, movidos.
    private static func movedIndices(_ pairs: [(a: Int, b: Int)]) -> Set<Int> {
        guard pairs.count > 1, pairs.count <= DiffOptions.maxMoveDetection else { return [] }
        let order = pairs.map(\.b)  // los índices en B, en el orden de A
        let sorted = order.sorted()  // el orden que tendrían sin moverse
        var dp = [[Int]](
            repeating: [Int](repeating: 0, count: sorted.count + 1),
            count: order.count + 1)
        for i in stride(from: order.count - 1, through: 0, by: -1) {
            for j in stride(from: sorted.count - 1, through: 0, by: -1) {
                dp[i][j] =
                    order[i] == sorted[j]
                    ? dp[i + 1][j + 1] + 1
                    : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var still = Set<Int>()
        var i = 0, j = 0
        while i < order.count && j < sorted.count {
            if order[i] == sorted[j] {
                still.insert(order[i]); i += 1; j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return Set(pairs.filter { !still.contains($0.b) }.map(\.a))
    }
}
