import Foundation

/// Deterministic Vietnamese currency formatter using dot grouping (`12.500.000đ`).
public enum VNDFormatter {
    public static func format(_ amount: Int) -> String {
        let isNegative = amount < 0
        let digits = Array(String(abs(amount)))
        var grouped = ""
        grouped.reserveCapacity(digits.count + digits.count / 3)

        for (offset, char) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 {
                grouped.append(".")
            }
            grouped.append(char)
        }

        let formatted = String(grouped.reversed())
        return "\(isNegative ? "-" : "")\(formatted)đ"
    }

    public static func formatSigned(_ amount: Int, direction: Direction) -> String {
        let prefix = direction == .out ? "-" : "+"
        return "\(prefix)\(format(amount))"
    }

    public static func formatDelta(_ delta: Int) -> String {
        if delta == 0 { return "Khớp 0đ" }
        let sign = delta > 0 ? "+" : "-"
        return "Lệch \(sign)\(format(abs(delta)))"
    }
}
