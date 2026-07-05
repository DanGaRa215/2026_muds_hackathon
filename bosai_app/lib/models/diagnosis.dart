/// 家具診断の結果1件（履歴保存用）
class Diagnosis {
  final int? id;
  final String createdAt; // ISO8601
  final String riskLevel; // '危険' | '注意' | 'おおむね安全'
  final String intensity; // 想定震度（例: '震度6強'）
  final String fixations; // カンマ区切りの固定状況
  final String comment;

  const Diagnosis({
    this.id,
    required this.createdAt,
    required this.riskLevel,
    required this.intensity,
    required this.fixations,
    required this.comment,
  });

  factory Diagnosis.fromMap(Map<String, dynamic> map) => Diagnosis(
        id: map['id'] as int?,
        createdAt: map['created_at'] as String,
        riskLevel: map['risk_level'] as String,
        intensity: map['intensity'] as String,
        fixations: map['fixations'] as String,
        comment: map['comment'] as String,
      );

  Map<String, dynamic> toMap() => {
        'created_at': createdAt,
        'risk_level': riskLevel,
        'intensity': intensity,
        'fixations': fixations,
        'comment': comment,
      };
}
