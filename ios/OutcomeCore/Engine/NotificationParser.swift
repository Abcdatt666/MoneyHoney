import Foundation

/// Notification parser for MBBank and MoMo push notifications.
public enum NotificationParser {
    private static let mbGdRegex = try! NSRegularExpression(
        pattern: #"GD\s*:\s*(?<sign>[+-])\s*(?<num>\d{1,3}(?:[.,]\d{3})+|\d+)(?:[.,]\d{2})?\s*(?:VND|VNĐ|Đ|D)?(?:\s+(?<dt>\d{2}/\d{2}/\d{2,4}\s+\d{2}:\d{2}(?::\d{2})?))?"#,
        options: [.caseInsensitive]
    )

    private static let signedAmountRegex = try! NSRegularExpression(
        pattern: #"(?<![\d/\-])(?<sign>[+-])\s*(?<num>\d{1,3}(?:[.,]\d{3})+|\d+)(?:[.,]\d{2})?\s*(?:VND|VNĐ|đ|Đ)?(?![\d/\-])"#,
        options: [.caseInsensitive]
    )

    private static let currencyAmountRegex = try! NSRegularExpression(
        pattern: #"(?<!\d)(?<num>\d{1,3}(?:[.,]\d{3})+|\d+)(?:[.,]\d{2})?\s*(?:VND|VNĐ|đ|Đ)(?=\s|[.,;:!?\)\"]|$)"#,
        options: [.caseInsensitive]
    )

    private static let prefixCurrencyAmountRegex = try! NSRegularExpression(
        pattern: #"\b(?:VND|VNĐ)\s*(?<num>\d{1,3}(?:[.,]\d{3})+|\d+)(?:[.,]\d{2})?(?!\d)"#,
        options: [.caseInsensitive]
    )

    private static let balanceRegex = try! NSRegularExpression(
        pattern: #"(?:SD|SO\s*DU|SỐ\s*DƯ)(?:\s+(?:KHA\s*DUNG|KHẢ\s*DỤNG|HIEN\s*TAI|HIỆN\s*TẠI|CON\s*LAI|CÒN\s*LẠI))?\s*[:\-]?\s*(?:(?:VND|VNĐ)\s*)?(?<num>\d{1,3}(?:[.,]\d{3})+|\d+)(?:[.,]\d{2})?\s*(?:VND|VNĐ|Đ|D)?"#,
        options: [.caseInsensitive]
    )

    private static let ndRegex = try! NSRegularExpression(
        pattern: #"(?:ND|NỘI\s*DUNG|NOI\s*DUNG)\s*:\s*(?<val>[^|\n]+)"#,
        options: [.caseInsensitive]
    )

    private static let traceRegex = try! NSRegularExpression(
        pattern: #"(?:-\s*)?(?:M[aã]\s+giao\s+d[iị]ch\s*/\s*Trace|Trace)\s*[:#]?\s*(?<trace>[A-Z0-9]+)\b"#,
        options: [.caseInsensitive]
    )

    private static let momoCashInRegex = try! NSRegularExpression(
        pattern: #"MOMO[\s_\-]?CASHIN"#,
        options: [.caseInsensitive]
    )

    private static let momoCashOutRegex = try! NSRegularExpression(
        pattern: #"MOMO[\s_\-]?CASHOUT"#,
        options: [.caseInsensitive]
    )

    private static let momoReceiveRegex = try! NSRegularExpression(
        pattern: #"^(?<sender>.+?)\s+(?:đã\s+)?(?:chuyển|gửi)\s+(?:tiền\s+)?(?:cho\s+bạn|đến\s+bạn)"#,
        options: [.caseInsensitive]
    )

    private static let momoReceivedFromRegex = try! NSRegularExpression(
        pattern: #"nhận\s+được\s+.*?\s+từ\s+(?<sender>.+?)(?:\s*\([0-9\s.+\-]+\)|\s+qua\s+[^.\n]+|\s*[.\n]|$)"#,
        options: [.caseInsensitive]
    )

    private static let momoPaymentRegex = try! NSRegularExpression(
        pattern: #"thanh\s+toán(?:\s+thành\s+công)?\s+.*?\s+(?:cho\s+dịch\s+vụ|cho|tại)\s+(?<merchant>[^.\n]+)"#,
        options: [.caseInsensitive]
    )

    private static let momoRefundRegex = try! NSRegularExpression(
        pattern: #"(?:được\s+hoàn|hoàn\s+tiền).*?\s+từ\s+(?:giao\s+dịch\s+)?(?<merchant>.+?)(?:\s+vào\s+Ví\s+MoMo|\s*[.\n]|$)"#,
        options: [.caseInsensitive]
    )

    private static let momoTransferOutRegex = try! NSRegularExpression(
        pattern: #"(?:đã\s+chuyển|chuyển\s+tiền(?:\s+thành\s+công)?)\s+.*?\s+(?:cho|đến|tới)\s+(?<recipient>[^.\n(]+)"#,
        options: [.caseInsensitive]
    )

    private static let momoMessageRegex = try! NSRegularExpression(
        pattern: #"L[ơờ]i\s+nh[ắa]n\s*:\s*(?<msg>.+)$"#,
        options: [.caseInsensitive]
    )

    private static let promoKeywords: [String] = [
        "UU DAI",
        "KHUYEN MAI",
        "GIAM GIA",
        "VOUCHER",
        "THE QUA",
        "QUA TANG",
        "NHAN NGAY",
        "CO HOI",
        "GIOI THIEU BAN BE",
        "TRUNG THUONG",
        "TANG BAN",
        "HOAN TIEN LEN DEN",
        "BAO TRI",
        "CAP NHAT UNG DUNG",
        "MA OTP",
        "OTP",
        // Credit card statements, debt reminders, savings books, and MoMo Postpaid
        "SAO KE",
        "DU NO",
        "HAN CHOT THANH TOAN",
        "VUI LONG THANH TOAN",
        "DEN HAN THANH TOAN",
        "THANH TOAN TOI THIEU",
        "PHAT SINH PHI TRE HAN",
        "THE TIN DUNG",
        "SO TIET KIEM",
        "TIET KIEM SO",
        "VI TRA SAU",
    ]

    private static let inPhrases: [String] = [
        "NHAN DUOC",
        "NHAN TIEN",
        "CHUYEN CHO BAN",
        "GUI CHO BAN",
        "CHUYEN DEN BAN",
        "CONG TIEN",
        "HOAN TIEN",
        "DUOC HOAN",
        "HOAN LAI",
        "NAP TIEN VAO VI",
        "VAO VI MOMO",
        "VE VI MOMO",
        "NAP VAO VI",
    ]

    private static let outPhrases: [String] = [
        "THANH TOAN",
        "CHUYEN TIEN",
        "CHUYEN KHOAN",
        "DA CHUYEN",
        "TRU TIEN",
        "BI TRU",
        "TRU PHI",
        "PHI DUY TRI",
        "PHI THUONG NIEN",
        "RUT TIEN",
        "DA RUT",
        "MUA THE",
        "NAP DIEN THOAI",
        "NAP TIEN DIEN THOAI",
        "NAP DATA",
        "NAP 4G",
        "TICH LUY",
        "CHUYEN DEN",
        "GUI DEN",
    ]

    public static func parse(_ raw: RawNotification) -> ParsedTransaction? {
        let combined = "\(raw.title) \(raw.body)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else { return nil }

        // Strip user-typed MoMo transfer message ("Lời nhắn: ...") before promo and
        // direction checks so words like "voucher" or "hoàn tiền" inside a note never
        // drop a real transfer or flip its direction.
        let combinedForMatching = replacingMatches(of: momoMessageRegex, in: combined, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let upperAscii = stripVietnameseAccents(combinedForMatching).uppercased()

        // Only a genuine checking-account movement ("GD: +/-[amount]") may bypass
        // promotional / statement / credit-card / postpaid reminder filters.
        let hasExplicitCheckingGd = firstMatch(of: mbGdRegex, in: combinedForMatching) != nil
        if promoKeywords.contains(where: { upperAscii.contains($0) }), !hasExplicitCheckingGd {
            return nil
        }

        // Dedicated Túi Thần Tài handling for MoMo main wallet accuracy:
        // - Daily interest accrues inside Túi Thần Tài (NOT main Ví MoMo cash balance) -> ignore.
        // - Withdraw from Túi Thần Tài back to Ví MoMo -> INCOME on Ví MoMo.
        // - Deposit / Auto-save from Ví MoMo into Túi Thần Tài -> EXPENSE on Ví MoMo.
        if raw.sourceApp == .momo, upperAscii.contains("TUI THAN TAI") {
            if upperAscii.contains("TIEN LOI") || upperAscii.contains("LAI SUAT") {
                return nil
            }
            let textNoSd = replacingMatches(of: balanceRegex, in: combinedForMatching, with: " ")
            guard let amount = extractFirstCurrencyAmount(in: textNoSd) else {
                return nil
            }
            if upperAscii.contains("VE VI MOMO") || (upperAscii.contains("RUT") && upperAscii.contains("TU TUI THAN TAI")) {
                return ParsedTransaction(
                    txType: .income,
                    sourceWalletId: .momo,
                    targetWalletId: nil,
                    amount: amount,
                    direction: .in,
                    description: "Rút Túi Thần Tài",
                    traceId: extractTraceId(from: combined),
                    reportedBalanceAfter: extractReportedBalance(from: combined),
                    occurredAt: raw.receivedAt
                )
            }
            if upperAscii.contains("VAO TUI THAN TAI") || upperAscii.contains("TICH LUY") {
                return ParsedTransaction(
                    txType: .expense,
                    sourceWalletId: .momo,
                    targetWalletId: nil,
                    amount: amount,
                    direction: .out,
                    description: "Nạp Túi Thần Tài",
                    traceId: extractTraceId(from: combined),
                    reportedBalanceAfter: extractReportedBalance(from: combined),
                    occurredAt: raw.receivedAt
                )
            }
            return nil
        }

        guard let extracted = extractAmountDirectionAndTime(from: combinedForMatching, fallbackDate: raw.receivedAt) else {
            return nil
        }

        let reportedBalance = extractReportedBalance(from: combined)
        let traceId = extractTraceId(from: combined)
        let description = extractDescription(rawTitle: raw.title, rawBody: raw.body)

        if raw.sourceApp == .mbbank {
            if firstMatch(of: momoCashInRegex, in: upperAscii) != nil, extracted.direction == .out {
                return ParsedTransaction(
                    txType: .internalTransfer,
                    sourceWalletId: .mbbank,
                    targetWalletId: .momo,
                    amount: extracted.amount,
                    direction: .out,
                    description: "Nạp tiền ví MoMo (MOMO-CASHIN)",
                    traceId: traceId,
                    reportedBalanceAfter: reportedBalance,
                    occurredAt: extracted.occurredAt
                )
            }
            if firstMatch(of: momoCashOutRegex, in: upperAscii) != nil, extracted.direction == .in {
                return ParsedTransaction(
                    txType: .internalTransfer,
                    sourceWalletId: .momo,
                    targetWalletId: .mbbank,
                    amount: extracted.amount,
                    direction: .in,
                    description: "Rút tiền từ MoMo về MBBank (MOMO-CASHOUT)",
                    traceId: traceId,
                    reportedBalanceAfter: reportedBalance,
                    occurredAt: extracted.occurredAt
                )
            }
        }

        let txType: TransactionType = extracted.direction == .out ? .expense : .income
        return ParsedTransaction(
            txType: txType,
            sourceWalletId: raw.sourceApp,
            targetWalletId: nil,
            amount: extracted.amount,
            direction: extracted.direction,
            description: description,
            traceId: traceId,
            reportedBalanceAfter: reportedBalance,
            occurredAt: extracted.occurredAt
        )
    }

    // MARK: - Helpers

    private static func stripVietnameseAccents(_ text: String) -> String {
        text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func parseVndInt(_ numText: String) -> Int? {
        let digits = numText.replacingOccurrences(of: #"[.,\s]"#, with: "", options: .regularExpression)
        return Int(digits)
    }

    private static func parseMbDatetime(_ dtText: String?, fallback: Date) -> Date {
        guard let dtText = dtText?.trimmingCharacters(in: .whitespacesAndNewlines), !dtText.isEmpty else {
            return fallback
        }
        let formats = ["dd/MM/yy HH:mm", "dd/MM/yyyy HH:mm", "dd/MM/yy HH:mm:ss", "dd/MM/yyyy HH:mm:ss"]
        for fmt in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = fmt
            if let parsed = formatter.date(from: dtText) {
                return parsed
            }
        }
        return fallback
    }

    private static func extractFirstCurrencyAmount(in text: String) -> Int? {
        if let suffix = firstMatch(of: currencyAmountRegex, in: text),
           let numStr = capturedGroup("num", in: suffix, text: text),
           let amount = parseVndInt(numStr), amount > 0 {
            return amount
        }
        if let prefix = firstMatch(of: prefixCurrencyAmountRegex, in: text),
           let numStr = capturedGroup("num", in: prefix, text: text),
           let amount = parseVndInt(numStr), amount > 0 {
            return amount
        }
        return nil
    }

    private static func extractAmountDirectionAndTime(
        from text: String,
        fallbackDate: Date
    ) -> (amount: Int, direction: Direction, occurredAt: Date)? {
        if let mbGd = firstMatch(of: mbGdRegex, in: text),
           let numStr = capturedGroup("num", in: mbGd, text: text),
           let signStr = capturedGroup("sign", in: mbGd, text: text),
           let amount = parseVndInt(numStr), amount > 0 {
            let direction: Direction = signStr == "-" ? .out : .in
            let occurredAt = parseMbDatetime(capturedGroup("dt", in: mbGd, text: text), fallback: fallbackDate)
            return (amount, direction, occurredAt)
        }

        let textNoSd = replacingMatches(of: balanceRegex, in: text, with: " ")

        if let signed = firstMatch(of: signedAmountRegex, in: textNoSd),
           let numStr = capturedGroup("num", in: signed, text: textNoSd),
           let signStr = capturedGroup("sign", in: signed, text: textNoSd),
           let amount = parseVndInt(numStr), amount > 0 {
            let direction: Direction = signStr == "-" ? .out : .in
            return (amount, direction, fallbackDate)
        }

        let upperAscii = stripVietnameseAccents(textNoSd).uppercased()
        if let amount = extractFirstCurrencyAmount(in: textNoSd) {
            if inPhrases.contains(where: { upperAscii.contains($0) }) {
                return (amount, .in, fallbackDate)
            }
            if outPhrases.contains(where: { upperAscii.contains($0) }) {
                return (amount, .out, fallbackDate)
            }
        }

        return nil
    }

    private static func extractReportedBalance(from text: String) -> Int? {
        guard let match = firstMatch(of: balanceRegex, in: text),
              let numStr = capturedGroup("num", in: match, text: text) else {
            return nil
        }
        return parseVndInt(numStr)
    }

    private static func extractTraceId(from text: String) -> String? {
        guard let match = firstMatch(of: traceRegex, in: text),
              let trace = capturedGroup("trace", in: match, text: text) else {
            return nil
        }
        return trace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMoMoMessage(from rawBody: String) -> String? {
        guard let msgMatch = firstMatch(of: momoMessageRegex, in: rawBody),
              let rawMsg = capturedGroup("msg", in: msgMatch, text: rawBody) else {
            return nil
        }
        let quoteSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”"))
        let cleaned = rawMsg.trimmingCharacters(in: quoteSet)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func extractDescription(rawTitle: String, rawBody: String) -> String {
        let combined = "\(rawTitle)\n\(rawBody)".trimmingCharacters(in: .whitespacesAndNewlines)
        let upperAscii = stripVietnameseAccents(combined).uppercased()

        if firstMatch(of: momoCashInRegex, in: upperAscii) != nil { return "MOMO-CASHIN" }
        if firstMatch(of: momoCashOutRegex, in: upperAscii) != nil { return "MOMO-CASHOUT" }

        let trimChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".:-|"))
        let simpleTrim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".:-"))

        if let ndMatch = firstMatch(of: ndRegex, in: combined),
           let val = capturedGroup("val", in: ndMatch, text: combined) {
            let cleaned = replacingMatches(of: traceRegex, in: val, with: "")
                .trimmingCharacters(in: trimChars)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        if let refundMatch = firstMatch(of: momoRefundRegex, in: rawBody),
           let merchantRaw = capturedGroup("merchant", in: refundMatch, text: rawBody) {
            let merchant = merchantRaw.trimmingCharacters(in: simpleTrim)
            if !merchant.isEmpty {
                return "Hoàn tiền - \(merchant)"
            }
        }

        let trimmedBody = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if let momoMatch = firstMatch(of: momoReceiveRegex, in: trimmedBody),
           let senderRaw = capturedGroup("sender", in: momoMatch, text: trimmedBody) {
            let sender = senderRaw.trimmingCharacters(in: simpleTrim)
            if let msg = extractMoMoMessage(from: rawBody) {
                return "\(sender) - \(msg)"
            }
            return sender
        }

        if let receivedFrom = firstMatch(of: momoReceivedFromRegex, in: rawBody),
           let senderRaw = capturedGroup("sender", in: receivedFrom, text: rawBody) {
            let sender = senderRaw.trimmingCharacters(in: simpleTrim)
            if let msg = extractMoMoMessage(from: rawBody) {
                return "\(sender) - \(msg)"
            }
            if !sender.isEmpty {
                return sender
            }
        }

        if let paymentMatch = firstMatch(of: momoPaymentRegex, in: rawBody),
           let merchantRaw = capturedGroup("merchant", in: paymentMatch, text: rawBody) {
            let merchant = merchantRaw.trimmingCharacters(in: simpleTrim)
            if !merchant.isEmpty {
                return merchant
            }
        }

        if let transferOut = firstMatch(of: momoTransferOutRegex, in: rawBody),
           let recipientRaw = capturedGroup("recipient", in: transferOut, text: rawBody) {
            let recipient = recipientRaw.trimmingCharacters(in: simpleTrim)
            if !recipient.isEmpty {
                return "Chuyển \(recipient)"
            }
        }

        var cleaned = replacingMatches(of: balanceRegex, in: rawBody, with: " ")
        cleaned = replacingMatches(of: traceRegex, in: cleaned, with: " ")
        cleaned = replacingMatches(of: signedAmountRegex, in: cleaned, with: " ")
        cleaned = replacingMatches(of: currencyAmountRegex, in: cleaned, with: " ")
        cleaned = replacingMatches(of: prefixCurrencyAmountRegex, in: cleaned, with: " ")
        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: trimChars)

        return cleaned.isEmpty ? "Không rõ nội dung" : cleaned
    }

    private static func firstMatch(of regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    private static func replacingMatches(
        of regex: NSRegularExpression,
        in text: String,
        with template: String
    ) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func capturedGroup(
        _ name: String,
        in match: NSTextCheckingResult,
        text: String
    ) -> String? {
        let nsRange = match.range(withName: name)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else {
            return nil
        }
        return String(text[range])
    }
}
