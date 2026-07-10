import 'dart:convert';

import 'package:bosai_app/widgets/diagnosis_result_card.dart';

/// 検出確認画面での detection 編集ロジック（v2.4）。
class DetectionEditor {
  static const List<String> allBraceClasses = [
    'brace_l_bracket',
    'brace_tension_rod',
    'brace_mat',
    'brace_belt',
    'brace_stopper',
  ];

  static Map<String, dynamic> deepCopy(Map<String, dynamic> detection) {
    return jsonDecode(jsonEncode(detection)) as Map<String, dynamic>;
  }

  static int initialSelectedIndex(List<dynamic> furniture) {
    var bestIndex = 0;
    var bestConfidence = -1.0;
    for (var i = 0; i < furniture.length; i++) {
      final item = furniture[i] as Map<String, dynamic>;
      final confidence = (item['confidence'] as num?)?.toDouble() ?? 0.0;
      if (confidence > bestConfidence) {
        bestConfidence = confidence;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  static Map<String, dynamic> selectedFurnitureItem(
    Map<String, dynamic> editedDetection,
    int selectedIndex,
  ) {
    final furniture =
        (editedDetection['furniture'] as List<dynamic>).cast<Map<String, dynamic>>();
    return furniture[selectedIndex];
  }

  /// 確定時に /diagnose へ送る detection（選択家具1件のみ）。
  static Map<String, dynamic> buildSubmissionDetection(
    Map<String, dynamic> editedDetection,
    int selectedIndex,
  ) {
    final furniture =
        (editedDetection['furniture'] as List<dynamic>).cast<Map<String, dynamic>>();
    final selected = Map<String, dynamic>.from(furniture[selectedIndex]);
    return {
      'furniture': [selected],
      'image_issues': List<dynamic>.from(
        editedDetection['image_issues'] as List<dynamic>? ?? [],
      ),
    };
  }

  static bool isBraceEnabled(Map<String, dynamic> furnitureItem, String braceClass) {
    final braces =
        (furnitureItem['braces'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    return braces.any((brace) => brace['class'] == braceClass);
  }

  static void setBraceEnabled(
    Map<String, dynamic> furnitureItem,
    String braceClass,
    bool enabled,
  ) {
    final braces = (furnitureItem['braces'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();

    if (enabled) {
      if (!braces.any((brace) => brace['class'] == braceClass)) {
        braces.add({
          'class': braceClass,
          'confidence': 1.0,
          'install_quality': 'unverified',
          'bbox': null,
        });
      }
    } else {
      braces.removeWhere((brace) => brace['class'] == braceClass);
    }

    furnitureItem['braces'] = braces;
  }

  static String furnitureRadioLabel(Map<String, dynamic> furnitureItem) {
    final cls = furnitureItem['class'] as String;
    final confidence = (furnitureItem['confidence'] as num?)?.toDouble();
    final label = furnitureLabel(cls);
    if (confidence == null) return label;
    return '$label  信頼度 ${confidence.toStringAsFixed(2)}';
  }
}
