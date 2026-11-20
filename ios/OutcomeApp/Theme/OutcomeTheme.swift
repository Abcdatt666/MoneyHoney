import OutcomeCore
import SwiftUI

/// Design tokens for Outcome's Tactile Bento native iOS visual system.
enum OutcomeTheme {
    enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let tileSpacing: CGFloat = 10
        static let cardRadius: CGFloat = 22
        static let tileRadius: CGFloat = 20
        static let chipRadius: CGFloat = 16
        static let minTouchTarget: CGFloat = 44
        static let chipMinHeight: CGFloat = 46
        static let primaryButtonHeight: CGFloat = 50
    }

    enum Colors {
        static let canvas = Color("SystemGroupedBackground")
        static let card = Color("SecondarySystemGroupedBackground")
        static let track = Color("TertiarySystemGroupedBackground")
        static let accent = Color.accentColor
        static let mbbankTile = Color("MBBankTileSurface")
        static let momoTile = Color("MoMoTileSurface")

        static let income = Color.green
        static let discrepancy = Color.red
        static let pending = Color.orange
    }

    static func symbol(for wallet: WalletId) -> String {
        switch wallet {
        case .mbbank:
            return "building.columns.fill"
        case .momo:
            return "wallet.pass.fill"
        }
    }

    static func symbol(forTagId tagId: String?) -> String {
        switch tagId {
        case "tag_an_uong":
            return "fork.knife"
        case "tag_cf":
            return "cup.and.saucer.fill"
        case "tag_di_chuyen":
            return "car.fill"
        case "tag_mua_sam":
            return "bag.fill"
        case "tag_hoa_don":
            return "doc.text.fill"
        case "tag_giai_tri":
            return "tv.fill"
        case "tag_tra_no":
            return "arrow.uturn.backward.circle.fill"
        case "tag_thu_nhap":
            return "arrow.down.left.circle.fill"
        case "tag_hoan_tien":
            return "arrow.counterclockwise.circle.fill"
        default:
            return "tag.fill"
        }
    }

    static func symbol(for tx: Transaction) -> String {
        if tx.txType == .internalTransfer {
            return "arrow.left.arrow.right"
        }
        return symbol(forTagId: tx.tagId)
    }

    static let chartPalette: [Color] = [
        .accentColor,
        .blue,
        .green,
        .purple,
        .teal,
        .orange,
    ]
}
