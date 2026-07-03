import Foundation
import UIKit

// MARK: - 列挙型

enum SeismicIntensity: String, CaseIterable, Identifiable {
    case fiveWeak  = "5弱"
    case fiveStrong = "5強"
    case sixWeak   = "6弱"
    case sixStrong  = "6強"
    case seven     = "7"

    var id: String { rawValue }

    /// 数値スコア(高いほど揺れが強い)
    var score: Int {
        switch self {
        case .fiveWeak:  return 1
        case .fiveStrong: return 2
        case .sixWeak:   return 3
        case .sixStrong:  return 4
        case .seven:     return 5
        }
    }
}

enum SoilType: String, CaseIterable, Identifiable {
    case hard   = "硬質"
    case normal = "普通"
    case soft   = "軟弱"

    var id: String { rawValue }

    var amplification: Double {
        switch self {
        case .hard:   return 0.8
        case .normal: return 1.0
        case .soft:   return 1.4
        }
    }
}

enum FixtureType: String, CaseIterable, Identifiable {
    case tensionPole  = "突っ張り棒"
    case lBracket     = "L字金具"
    case quakeMat     = "耐震マット"
    case none         = "固定なし"

    var id: String { rawValue }

    var reductionScore: Double {
        switch self {
        case .tensionPole: return 0.6
        case .lBracket:    return 0.3
        case .quakeMat:    return 0.7
        case .none:        return 1.0
        }
    }
}

enum BuildingType: String, CaseIterable, Identifiable {
    case wooden = "木造"
    case rc     = "RC"

    var id: String { rawValue }

    var amplification: Double {
        switch self {
        case .wooden: return 1.3
        case .rc:     return 1.0
        }
    }
}

// MARK: - 入力データ

struct DiagnosisInput {
    var seismicIntensity: SeismicIntensity = .sixWeak
    var soil: SoilType = .normal
    var fixtures: Set<FixtureType> = [.none]
    var building: BuildingType = .wooden
    var floor: Int = 1
}

// MARK: - 結果データ

struct DiagnosisResult {
    enum Level: String {
        case safe    = "safe"
        case warning = "warning"
        case danger  = "danger"

        var display: String {
            switch self {
            case .safe:    return "安全"
            case .warning: return "要改善"
            case .danger:  return "危険"
            }
        }
    }

    let level: Level
    let advice: String
}

// MARK: - 座標

struct Coordinate {
    let lat: Double
    let lon: Double
}

// MARK: - 経路情報

struct RouteInfo {
    let distance: Double       // メートル
    let bearingDegrees: Double // 方位角(北=0, 時計回り)
    let destinationName: String
}
