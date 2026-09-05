import Foundation
import IndieCore

public indirect enum VDFValue: Sendable, Equatable {
    case string(String)
    case object([String: VDFValue])

    public var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public var object: [String: VDFValue]? {
        if case .object(let value) = self { value } else { nil }
    }
}

public enum VDFParser {
    private enum Token: Equatable { case text(String), open, close }

    public static func parse(data: Data) throws -> [String: VDFValue] {
        guard let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw IndieError.invalidData(L("VDF 文本编码无效"))
        }
        var tokens = try tokenize(source)
        var index = 0
        return try parseObject(tokens: &tokens, index: &index, expectsClose: false)
    }

    public static func parse(url: URL) throws -> [String: VDFValue] { try parse(data: Data(contentsOf: url)) }

    private static func parseObject(tokens: inout [Token], index: inout Int, expectsClose: Bool) throws -> [String: VDFValue] {
        var object: [String: VDFValue] = [:]
        while index < tokens.count {
            if tokens[index] == .close {
                guard expectsClose else { throw IndieError.invalidData(L("VDF 出现多余的右花括号")) }
                index += 1
                return object
            }
            guard case .text(let key) = tokens[index] else { throw IndieError.invalidData(L("VDF 缺少键")) }
            index += 1
            guard index < tokens.count else { throw IndieError.invalidData(L("VDF 键 \(key) 缺少值")) }
            switch tokens[index] {
            case .text(let value):
                object[key] = .string(value)
                index += 1
            case .open:
                index += 1
                object[key] = .object(try parseObject(tokens: &tokens, index: &index, expectsClose: true))
            case .close:
                throw IndieError.invalidData(L("VDF 键 \(key) 缺少值"))
            }
        }
        if expectsClose { throw IndieError.invalidData(L("VDF 缺少右花括号")) }
        return object
    }

    private static func tokenize(_ source: String) throws -> [Token] {
        var result: [Token] = []
        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]
            if character.isWhitespace { index = source.index(after: index); continue }
            if character == "/", source.index(after: index) < source.endIndex, source[source.index(after: index)] == "/" {
                while index < source.endIndex, source[index] != "\n" { index = source.index(after: index) }
                continue
            }
            if character == "{" { result.append(.open); index = source.index(after: index); continue }
            if character == "}" { result.append(.close); index = source.index(after: index); continue }
            guard character == "\"" else { throw IndieError.invalidData(L("VDF 仅支持带引号的键值")) }
            index = source.index(after: index)
            var value = ""
            var closed = false
            while index < source.endIndex {
                let current = source[index]
                index = source.index(after: index)
                if current == "\"" { closed = true; break }
                if current == "\\", index < source.endIndex {
                    let escaped = source[index]
                    index = source.index(after: index)
                    switch escaped {
                    case "n": value.append("\n")
                    case "t": value.append("\t")
                    default: value.append(escaped)
                    }
                } else { value.append(current) }
            }
            guard closed else { throw IndieError.invalidData(L("VDF 字符串未闭合")) }
            result.append(.text(value))
        }
        return result
    }
}
