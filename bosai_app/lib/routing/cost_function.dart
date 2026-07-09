import 'graph.dart';
import 'models.dart';

/// 重みテーブル(§5.1)。値の差し替えはこのクラスのみで完結する。
/// ペナルティはすべて非負のメートル換算。
class RoutingWeights {
  RoutingWeights._();

  // 水域近接(弱): 50 <= water_dist_m < 100
  static const double waterWeakEarthquake = 100;
  static const double waterWeakFlood = 300;
  static const double waterWeakThresholdM = 100;

  // 水域近接(強): water_dist_m < 50(弱と排他)
  static const double waterStrongEarthquake = 200;
  static const double waterStrongFlood = 600;
  static const double waterStrongThresholdM = 50;

  // 橋(ソフトペナルティ。江戸川区では橋が広域避難の必須経路のため一律禁止しない)
  static const double bridgeEarthquake = 600;
  static const double bridgeFlood = 300;

  // トンネル/アンダーパス。floodは通常ハード制約(§5.3)、
  // フォールバック時のみ以下のソフトペナルティに緩める
  static const double tunnelEarthquake = 400;
  static const double tunnelFloodFallback = 3000;

  // 低標高: max(0, 2.0 - elevation_m) * k
  static const double lowElevationThresholdM = 2.0;
  static const double lowElevationKEarthquake = 0;
  static const double lowElevationKFlood = 150;

  // プロファイル係数(ペナルティにのみ乗算、距離には掛けない)
  static const double factorFastest = 0.5;
  static const double factorBalanced = 1.0;
  static const double factorSafest = 2.0;

  static double profileFactor(WeightProfile profile) {
    switch (profile) {
      case WeightProfile.fastest:
        return factorFastest;
      case WeightProfile.balanced:
        return factorBalanced;
      case WeightProfile.safest:
        return factorSafest;
    }
  }
}

/// モード×プロファイルのエッジコスト計算とエッジフィルタ。
/// EdgeCost(e) = lengthM + profileFactor × Σ penalty_i(e)
class CostFunction {
  final DisasterMode mode;
  final WeightProfile profile;

  /// true のとき flood のトンネルハード制約を +3000m ソフトペナルティに緩める(§5.3)
  final bool tunnelFallback;

  final double _factor;

  CostFunction({
    required this.mode,
    required this.profile,
    this.tunnelFallback = false,
  }) : _factor = RoutingWeights.profileFactor(profile);

  /// エッジフィルタ。floodモード(非フォールバック)では is_tunnel を通行不可とする。
  bool allows(Graph graph, int edgeIndex) {
    if (mode == DisasterMode.flood &&
        !tunnelFallback &&
        graph.isTunnel(edgeIndex)) {
      return false;
    }
    return true;
  }

  /// プロファイル係数適用前の生ペナルティ合計(m換算)。
  double rawPenalty(Graph graph, int edgeIndex) {
    var penalty = 0.0;
    final flood = mode == DisasterMode.flood;

    final waterDist = graph.waterDistM[edgeIndex];
    if (waterDist < RoutingWeights.waterStrongThresholdM) {
      penalty += flood
          ? RoutingWeights.waterStrongFlood
          : RoutingWeights.waterStrongEarthquake;
    } else if (waterDist < RoutingWeights.waterWeakThresholdM) {
      penalty += flood
          ? RoutingWeights.waterWeakFlood
          : RoutingWeights.waterWeakEarthquake;
    }

    if (graph.isBridge(edgeIndex)) {
      penalty +=
          flood ? RoutingWeights.bridgeFlood : RoutingWeights.bridgeEarthquake;
    }

    if (graph.isTunnel(edgeIndex)) {
      if (flood) {
        // 非フォールバック時は allows() で除外済み。ここに来るのは緩和後のみ。
        if (tunnelFallback) {
          penalty += RoutingWeights.tunnelFloodFallback;
        }
      } else {
        penalty += RoutingWeights.tunnelEarthquake;
      }
    }

    final k = flood
        ? RoutingWeights.lowElevationKFlood
        : RoutingWeights.lowElevationKEarthquake;
    if (k > 0) {
      final elevation = graph.elevationM[edgeIndex];
      final deficit = RoutingWeights.lowElevationThresholdM - elevation;
      if (deficit > 0) {
        penalty += deficit * k;
      }
    }

    return penalty;
  }

  /// EdgeCost = 実距離 + プロファイル係数 × 生ペナルティ
  double cost(Graph graph, int edgeIndex) {
    return graph.lengthM[edgeIndex] + _factor * rawPenalty(graph, edgeIndex);
  }
}
