import Foundation

/// Default category tag seed definitions matching Python Phase 1 core.
public enum DefaultTagSpecs {
    public struct Spec: Sendable {
        public let id: String
        public let name: String
    }

    public static let all: [Spec] = [
        Spec(id: "tag_an_uong", name: "Ăn uống"),
        Spec(id: "tag_cf", name: "CF"),
        Spec(id: "tag_di_chuyen", name: "Di chuyển"),
        Spec(id: "tag_mua_sam", name: "Mua sắm"),
        Spec(id: "tag_hoa_don", name: "Hóa đơn"),
        Spec(id: "tag_giai_tri", name: "Giải trí"),
        Spec(id: "tag_tra_no", name: "Trả nợ"),
        Spec(id: "tag_thu_nhap", name: "Thu nhập"),
        Spec(id: "tag_hoan_tien", name: "Hoàn tiền / Được trả"),
    ]
}
