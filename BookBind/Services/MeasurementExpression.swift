import Foundation

/// The unit length fields display in (Settings ▸ Units). Values are always stored in millimeters.
enum MeasurementUnit: String, CaseIterable, Identifiable {
    case millimeters = "mm"
    case inches = "in"

    static let storageKey = "measurementUnit"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .millimeters: return "Millimeters"
        case .inches: return "Inches"
        }
    }

    var suffix: String { rawValue }

    var millimetersPerUnit: Double {
        switch self {
        case .millimeters: return 1
        case .inches: return 25.4
        }
    }

    func fromMillimeters(_ mm: Double) -> Double { mm / millimetersPerUnit }
    func toMillimeters(_ value: Double) -> Double { value * millimetersPerUnit }

    /// Inches need more decimals than millimeters to hold the same precision.
    func fractionDigits(forMillimeterDigits digits: Int) -> Int {
        switch self {
        case .millimeters: return digits
        case .inches: return min(3, digits + 2)
        }
    }

    static var current: MeasurementUnit {
        UserDefaults.standard.string(forKey: storageKey).flatMap(MeasurementUnit.init(rawValue:)) ?? .millimeters
    }
}

/// Evaluates what a binder types into a measurement field.
///
/// Accepts any unit and simple arithmetic, the way page-layout apps do: `6in`, `6"`, `152mm`,
/// `15cm`, `12pt`, picas as `1p6` or `p6`, `229 - 2*3`, `(6in - 3mm) / 2`, and `50%` of a base.
/// A bare number takes the field's own unit. Approach inspired by DesignCraft's measurement
/// fields (storytold/designcraft, MIT OR Apache-2.0); this is an independent Swift implementation.
enum MeasurementExpression {
    /// Result in millimeters, or `nil` if the text isn't a valid measurement.
    /// - Parameters:
    ///   - defaultUnit: unit for bare numbers.
    ///   - baseMM: value `%` is relative to (usually the field's current value).
    static func evaluateLength(_ text: String, defaultUnit: MeasurementUnit, baseMM: Double? = nil) -> Double? {
        var parser = Parser(text: text, defaultMM: defaultUnit.millimetersPerUnit, base: baseMM, allowsUnits: true)
        return parser.parse()?.amount
    }

    /// Plain number with arithmetic (no units): page counts, GSM, angles, ratios.
    static func evaluateNumber(_ text: String, base: Double? = nil) -> Double? {
        var parser = Parser(text: text, defaultMM: 1, base: base, allowsUnits: false)
        return parser.parse()?.amount
    }

    // MARK: - Parser

    /// `amount` is millimeters when `hasUnit` or in a length field; `scalar` is the bare number.
    private struct Value {
        var amount: Double
        var scalar: Double
        var hasUnit: Bool
    }

    private static let unitMillimeters: [String: Double] = [
        "mm": 1,
        "cm": 10,
        "in": 25.4,
        "\"": 25.4,
        "″": 25.4,
        "pt": 25.4 / 72,
        "pc": 25.4 / 6
    ]

    private struct Parser {
        let chars: [Character]
        let defaultMM: Double
        let base: Double?
        let allowsUnits: Bool
        var index = 0

        init(text: String, defaultMM: Double, base: Double?, allowsUnits: Bool) {
            self.chars = Array(text.lowercased().replacingOccurrences(of: ",", with: "."))
            self.defaultMM = defaultMM
            self.base = base
            self.allowsUnits = allowsUnits
        }

        mutating func parse() -> Value? {
            guard let value = expression() else { return nil }
            skipSpaces()
            guard index == chars.count, value.amount.isFinite else { return nil }
            return value
        }

        // expression := term (("+" | "-") term)*
        private mutating func expression() -> Value? {
            guard var lhs = term() else { return nil }
            while let op = peekOperator(in: "+-") {
                index += 1
                guard let rhs = term() else { return nil }
                let sign: Double = op == "+" ? 1 : -1
                lhs = Value(
                    amount: lhs.amount + sign * rhs.amount,
                    scalar: lhs.scalar + sign * rhs.scalar,
                    hasUnit: lhs.hasUnit || rhs.hasUnit
                )
            }
            return lhs
        }

        // term := factor (("*" | "×" | "/" | "÷") factor)*
        private mutating func term() -> Value? {
            guard var lhs = factor() else { return nil }
            while let op = peekOperator(in: "*×/÷") {
                index += 1
                guard let rhs = factor() else { return nil }
                if op == "*" || op == "×" {
                    // Length × number scales the length; length × length isn't a length.
                    switch (lhs.hasUnit, rhs.hasUnit) {
                    case (_, false): lhs = Value(amount: lhs.amount * rhs.scalar, scalar: lhs.scalar * rhs.scalar, hasUnit: lhs.hasUnit)
                    case (false, true): lhs = Value(amount: rhs.amount * lhs.scalar, scalar: rhs.scalar * lhs.scalar, hasUnit: true)
                    case (true, true): return nil
                    }
                } else {
                    guard !rhs.hasUnit, rhs.scalar != 0 else { return nil }
                    lhs = Value(amount: lhs.amount / rhs.scalar, scalar: lhs.scalar / rhs.scalar, hasUnit: lhs.hasUnit)
                }
            }
            return lhs
        }

        // factor := ("-" | "+") factor | "(" expression ")" | quantity
        private mutating func factor() -> Value? {
            skipSpaces()
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c == "-" || c == "+" {
                index += 1
                guard let inner = factor() else { return nil }
                return c == "-" ? Value(amount: -inner.amount, scalar: -inner.scalar, hasUnit: inner.hasUnit) : inner
            }
            if c == "(" {
                index += 1
                guard let inner = expression() else { return nil }
                skipSpaces()
                guard index < chars.count, chars[index] == ")" else { return nil }
                index += 1
                return inner
            }
            return quantity()
        }

        // quantity := number [unit | "%" | "p" number]  |  "p" number
        private mutating func quantity() -> Value? {
            skipSpaces()
            // Points-only pica notation: "p6".
            if allowsUnits, index < chars.count, chars[index] == "p", index + 1 < chars.count, chars[index + 1].isNumber {
                index += 1
                guard let points = number() else { return nil }
                return lengthValue(mm: points * 25.4 / 72)
            }
            guard let n = number() else { return nil }
            skipSpaces()

            if index < chars.count, chars[index] == "%" {
                index += 1
                guard let base else { return nil }
                return Value(amount: base * n / 100, scalar: base * n / 100, hasUnit: allowsUnits)
            }

            guard allowsUnits else {
                return Value(amount: n, scalar: n, hasUnit: false)
            }

            // Picas and points: "1p6" = 1 pica + 6 points.
            if index < chars.count, chars[index] == "p",
               !(index + 1 < chars.count && (chars[index + 1] == "t" || chars[index + 1] == "c")) {
                index += 1
                let points = number() ?? 0
                return lengthValue(mm: n * 25.4 / 6 + points * 25.4 / 72)
            }

            // Longest matching unit suffix.
            for length in [2, 1] where index + length <= chars.count {
                let token = String(chars[index..<(index + length)])
                if let mmPerUnit = unitMillimeters[token] {
                    index += length
                    return lengthValue(mm: n * mmPerUnit)
                }
            }
            // A stray letter is a typo, not a measurement.
            if index < chars.count, chars[index].isLetter { return nil }
            return Value(amount: n * defaultMM, scalar: n, hasUnit: false)
        }

        private func lengthValue(mm: Double) -> Value {
            Value(amount: mm, scalar: mm / defaultMM, hasUnit: true)
        }

        private mutating func number() -> Double? {
            let start = index
            while index < chars.count, chars[index].isNumber || chars[index] == "." {
                index += 1
            }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]))
        }

        private mutating func peekOperator(in set: String) -> Character? {
            skipSpaces()
            guard index < chars.count, set.contains(chars[index]) else { return nil }
            return chars[index]
        }

        private mutating func skipSpaces() {
            while index < chars.count, chars[index].isWhitespace {
                index += 1
            }
        }
    }
}
