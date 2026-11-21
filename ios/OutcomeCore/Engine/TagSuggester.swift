import Foundation

/// Offline, zero-cloud tag recommender powered by merchant normalization,
/// personal confirmation history, and Vietnamese cold-start keyword rules.
public enum TagSuggester {
    private static let noiseTokens: Set<String> = [
        "chuyen", "tien", "khoan", "thanh", "toan", "dich", "vu", "giao", "ngan",
        "hang", "cho", "ban", "tu", "den", "qua", "tai", "vao", "vi", "momo",
        "mbbank", "vietqr", "nhanh", "trace", "nd", "gd", "sd", "vnd", "khong",
        "ro", "noi", "dung", "don", "nhap", "tay",
    ]

    private static let expenseRules: [(tagId: String, keywords: [String])] = [
        ("tag_cf", [
            "highlands", "phuc long", "starbucks", "katinat", "the coffee house",
            "cong ca phe", "tra sua", "gong cha", "koi", "tocotoco", "mixue",
            "phe la", "cafe", "ca phe", "coffee", "cf",
        ]),
        ("tag_an_uong", [
            "grabfood", "shopeefood", "befood", "com", "pho", "bun", "banh mi",
            "lau", "nuong", "an trua", "an toi", "an sang", "pizza", "kfc",
            "lotteria", "mcdonald", "jollibee", "circle k", "gs25", "ministop",
            "winmart", "bach hoa xanh", "coopmart", "aeon", "sieu thi", "nha hang",
        ]),
        ("tag_di_chuyen", [
            "grab", "xanh sm", "gsm", "be ", "xang", "petrolimex", "pvoil",
            "gui xe", "ve xe", "ve may bay", "vietjet", "vietnam airlines",
            "bamboo", "metro", "taxi", "xe om", "thu phi", "vetc", "epass",
        ]),
        ("tag_mua_sam", [
            "shopee", "lazada", "tiki", "tiktok shop", "uniqlo", "zara", "hasaki",
            "guardian", "mua sam", "the gioi di dong", "cellphones", "fpt shop",
            "dien may xanh", "con cung", "decathlon",
        ]),
        ("tag_hoa_don", [
            "apple services", "icloud", "app store", "google", "evn", "tien dien",
            "tien nuoc", "internet", "fpt telecom", "viettel", "vnpt", "mobifone",
            "vinaphone", "dien thoai", "nha tro", "tien nha", "phi quan ly", "hoa don",
        ]),
        ("tag_giai_tri", [
            "cgv", "lotte cinema", "galaxy", "beta", "spotify", "netflix",
            "youtube", "steam", "game", "bida", "karaoke", "du lich", "khach san",
            "agoda", "booking", "traveloka",
        ]),
        ("tag_tra_no", [
            "tra no", "gui lai", "tra tien", "vay", "muon", "hoan lai",
        ]),
    ]

    private static let incomeRules: [(tagId: String, keywords: [String])] = [
        ("tag_hoan_tien", [
            "hoan tien", "duoc hoan", "refund", "tra no", "chia tien", "campuchia",
        ]),
        ("tag_thu_nhap", [
            "luong", "salary", "thuong", "bonus", "tien loi", "tui than tai",
            "lai suat", "co tuc", "thu nhap",
        ]),
    ]

    /// Normalize a transaction description into an accent-stripped lowercase key.
    public static func normalizeMerchantKey(_ text: String) -> String {
        let stripped = text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        let tokens = stripped
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                guard token.count >= 2 else { return false }
                if token.allSatisfy(\.isNumber) { return false }
                return !noiseTokens.contains(token)
            }

        return tokens.joined(separator: " ")
    }

    /// Return up to `limit` ranked `Tag` suggestions for a transaction using
    /// personal confirmed history first, then built-in Vietnamese keyword rules.
    public static func suggest(
        for tx: Transaction,
        history: [Transaction],
        availableTags: [Tag],
        limit: Int = 3
    ) -> [Tag] {
        guard limit > 0, !availableTags.isEmpty else { return [] }

        let tagsById = Dictionary(uniqueKeysWithValues: availableTags.map { ($0.id, $0) })
        let targetKey = normalizeMerchantKey("\(tx.description) \(tx.note)")
        let targetTokens = Set(targetKey.split(separator: " ").map(String.init).filter { $0.count >= 3 })
        let rawNormalized = stripToLowerAscii("\(tx.description) \(tx.note)")

        var scores: [String: Int] = [:]
        var directionFreq: [String: Int] = [:]

        // 1) Personal history learning (confirmed transactions of the same direction)
        for past in history {
            guard past.id != tx.id,
                  past.status == .confirmed,
                  past.direction == tx.direction,
                  let tagId = past.tagId,
                  tagsById[tagId] != nil else {
                continue
            }

            directionFreq[tagId, default: 0] += 1

            guard !targetKey.isEmpty else { continue }
            let pastKey = normalizeMerchantKey("\(past.description) \(past.note)")
            guard !pastKey.isEmpty else { continue }

            if pastKey == targetKey {
                scores[tagId, default: 0] += 120
            } else if pastKey.contains(targetKey) || targetKey.contains(pastKey) {
                scores[tagId, default: 0] += 70
            } else {
                let pastTokens = Set(pastKey.split(separator: " ").map(String.init).filter { $0.count >= 3 })
                let overlap = targetTokens.intersection(pastTokens).count
                if overlap > 0 {
                    scores[tagId, default: 0] += overlap * 35
                }
            }
        }

        // 2) Built-in Vietnamese cold-start keyword rules
        let rules = tx.direction == .out ? expenseRules : incomeRules
        for rule in rules where tagsById[rule.tagId] != nil {
            for kw in rule.keywords {
                if rawNormalized.contains(kw) {
                    scores[rule.tagId, default: 0] += 50
                    break
                }
            }
        }

        // 3) Rank scored tags, then fill remaining slots with most-used / sensible defaults
        var orderedTagIds: [String] = scores
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                let lFreq = directionFreq[lhs.key, default: 0]
                let rFreq = directionFreq[rhs.key, default: 0]
                if lFreq != rFreq { return lFreq > rFreq }
                return (tagsById[lhs.key]?.sortOrder ?? 999) < (tagsById[rhs.key]?.sortOrder ?? 999)
            }
            .map(\.key)

        // Fill with user's most-frequently confirmed tags in this direction
        let freqFallback = directionFreq
            .sorted { $0.value > $1.value }
            .map(\.key)
        for tagId in freqFallback where !orderedTagIds.contains(tagId) {
            orderedTagIds.append(tagId)
        }

        // Fill with sensible direction defaults
        let defaultFallback: [String] = tx.direction == .out
            ? ["tag_an_uong", "tag_cf", "tag_mua_sam", "tag_di_chuyen", "tag_hoa_don"]
            : ["tag_thu_nhap", "tag_hoan_tien", "tag_tra_no"]
        for tagId in defaultFallback where tagsById[tagId] != nil && !orderedTagIds.contains(tagId) {
            orderedTagIds.append(tagId)
        }

        // Final fallback: any remaining available tags in sortOrder
        for tag in availableTags where !orderedTagIds.contains(tag.id) {
            orderedTagIds.append(tag.id)
        }

        return orderedTagIds
            .prefix(limit)
            .compactMap { tagsById[$0] }
    }

    private static func stripToLowerAscii(_ text: String) -> String {
        text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}
