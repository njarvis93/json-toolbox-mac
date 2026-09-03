import Foundation

public struct AlignedRow: Equatable {
    public enum Kind: Equatable { case equal, added, removed }
    public let left: String?
    public let right: String?
    public let leftNumber: Int?
    public let rightNumber: Int?
    public let kind: Kind
}

/// Alinea dos documentos ya formateados línea a línea, para la vista lado a lado.
/// Va *encima* del diff estructural: este solo decide dónde insertar huecos.
public enum LineAlignment {
    /// Por encima de este producto de longitudes se cae a un alineado posicional
    /// en vez de gastar memoria en la matriz de LCS.
    public static let maxCells = 1_400 * 1_400

    public static func align(_ a: [String], _ b: [String]) -> [AlignedRow] {
        var rows: [AlignedRow] = []
        var la = 0, lb = 0

        func emit(_ left: String?, _ right: String?, _ kind: AlignedRow.Kind) {
            if left != nil { la += 1 }
            if right != nil { lb += 1 }
            rows.append(
                AlignedRow(
                    left: left, right: right,
                    leftNumber: left == nil ? nil : la,
                    rightNumber: right == nil ? nil : lb,
                    kind: kind))
        }

        // Prefijo y sufijo comunes: la mayor parte de dos ficheros parecidos.
        var head = 0
        while head < a.count && head < b.count && a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < a.count - head && tail < b.count - head
            && a[a.count - 1 - tail] == b[b.count - 1 - tail]
        { tail += 1 }

        for i in 0..<head { emit(a[i], b[i], .equal) }

        let midA = Array(a[head..<(a.count - tail)])
        let midB = Array(b[head..<(b.count - tail)])

        if midA.count * midB.count <= maxCells {
            // LCS clásico; la matriz se recorre hacia atrás para reconstruir.
            var dp = [[Int]](
                repeating: [Int](repeating: 0, count: midB.count + 1),
                count: midA.count + 1)
            if midA.count > 0 && midB.count > 0 {
                for i in stride(from: midA.count - 1, through: 0, by: -1) {
                    for j in stride(from: midB.count - 1, through: 0, by: -1) {
                        dp[i][j] =
                            midA[i] == midB[j]
                            ? dp[i + 1][j + 1] + 1
                            : max(dp[i + 1][j], dp[i][j + 1])
                    }
                }
            }
            var i = 0, j = 0
            while i < midA.count && j < midB.count {
                if midA[i] == midB[j] {
                    emit(midA[i], midB[j], .equal); i += 1; j += 1
                } else if dp[i + 1][j] >= dp[i][j + 1] {
                    emit(midA[i], nil, .removed); i += 1
                } else {
                    emit(nil, midB[j], .added); j += 1
                }
            }
            while i < midA.count { emit(midA[i], nil, .removed); i += 1 }
            while j < midB.count { emit(nil, midB[j], .added); j += 1 }
        } else {
            for k in 0..<max(midA.count, midB.count) {
                let l = k < midA.count ? midA[k] : nil
                let r = k < midB.count ? midB[k] : nil
                emit(l, r, l == r ? .equal : (r == nil ? .removed : .added))
            }
        }

        for k in 0..<tail {
            emit(a[a.count - tail + k], b[b.count - tail + k], .equal)
        }
        return rows
    }

    public static func align(textA: String, textB: String) -> [AlignedRow] {
        align(textA.components(separatedBy: "\n"), textB.components(separatedBy: "\n"))
    }
}
