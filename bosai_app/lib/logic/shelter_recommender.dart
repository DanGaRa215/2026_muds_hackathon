import 'dart:math';

import '../models/shelter.dart';

/// 避難所推薦ロジック【メンバーB担当領域】
///
/// 本ファイルはダミー実装。設計書 Part B「メンバーB」の
/// スコアリング関数（距離/海抜/海岸距離/状況チェックの重み設計・
/// 16パターン検証）が完成したらこのクラスを差し替える。
class ShelterRecommender {
  /// 状況チェック（injury/fire/collapse/tsunami）を受け取り、
  /// スコア昇順（良い順）で最大5件を返す。
  static List<Shelter> recommend({
    required List<Shelter> shelters,
    required Set<String> situation,
    required double currentLat,
    required double currentLon,
  }) {
    double score(Shelter s) {
      final d = distanceM(currentLat, currentLon, s.lat, s.lon);
      // 基本スコア = 距離（近いほど良い）
      var sc = d;
      if (situation.contains('tsunami')) {
        // 津波時: 海抜が高く・海岸から遠いほど優先（沿岸部優先ルールの仮実装）
        sc = d * 0.5 - s.elevationM * 500 - s.coastDistanceM * 0.2;
        if (!s.supports('tsunami')) sc += 100000; // 津波非対応は大幅減点
      }
      if (situation.contains('fire') && !s.supports('fire')) {
        sc += 50000; // 火災時は火災対応外を後回し
      }
      return sc;
    }

    final sorted = [...shelters]..sort((a, b) => score(a).compareTo(score(b)));
    return sorted.take(5).toList();
  }

  /// 2点間距離（メートル）: ハバーサイン公式
  static double distanceM(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;

  /// 徒歩所要時間（分）: 80m/分で概算
  static int walkMinutes(double meters) => (meters / 80).ceil();
}
