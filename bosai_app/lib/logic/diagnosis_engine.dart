/// AI家具診断エンジン【メンバーA担当領域】
///
/// 将来: tflite_flutter による YOLOv8(TFLite) オンデバイス推論に差し替える。
/// UI側は抽象クラス `DiagnosisEngine` にのみ依存させることで、
/// モック → 本実装の入れ替えを1行で行えるようにしている。
abstract class DiagnosisEngine {
  Future<DiagnosisResult> analyze({
    String? imagePath, // モックでは未使用。TFLite実装で推論入力に使う
    required String intensity, // 想定震度（'震度5弱'〜'震度7'）
    required List<String> fixations, // 固定状況チェック
  });
}

class DiagnosisResult {
  final String riskLevel; // '危険' | '注意' | 'おおむね安全'
  final String comment;
  final List<String> suggestions;

  const DiagnosisResult({
    required this.riskLevel,
    required this.comment,
    required this.suggestions,
  });
}

/// ルールベースのモック判定（デモ用）
class MockDiagnosisEngine implements DiagnosisEngine {
  @override
  Future<DiagnosisResult> analyze({
    String? imagePath,
    required String intensity,
    required List<String> fixations,
  }) async {
    // 推論している風の待ち時間（TFLite実装時は実推論に置き換え）
    await Future.delayed(const Duration(milliseconds: 800));

    final hasFix = fixations.isNotEmpty && !fixations.contains('固定なし');
    final severe = intensity == '震度6強' || intensity == '震度7';

    if (!hasFix && severe) {
      return const DiagnosisResult(
        riskLevel: '危険',
        comment: '固定なしの家具は震度6強以上で転倒する可能性が高いです。',
        suggestions: ['L字金具＋突っ張り棒の併用を推奨', '寝室・出入口付近から家具を移動'],
      );
    }
    if (!hasFix) {
      return const DiagnosisResult(
        riskLevel: '注意',
        comment: '固定措置が確認できません。中規模の揺れでも移動・転倒の恐れがあります。',
        suggestions: ['まず突っ張り棒か耐震マットを設置', '重い物は下段に収納'],
      );
    }
    if (severe && fixations.length == 1) {
      return const DiagnosisResult(
        riskLevel: '注意',
        comment: '単一の固定措置のみです。震度6強以上では複数の固定方法の併用が推奨されます。',
        suggestions: ['突っ張り棒はL字金具や耐震マットと併用', '天井との隙間・強度を確認'],
      );
    }
    return const DiagnosisResult(
      riskLevel: 'おおむね安全',
      comment: '複数の固定措置が確認できました。定期的な緩み点検を続けてください。',
      suggestions: ['半年に一度、突っ張り棒の緩みを確認'],
    );
  }
}
