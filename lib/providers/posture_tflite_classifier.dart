import 'dart:math';
import 'package:tflite_flutter/tflite_flutter.dart';

/// TensorFlow Lite 기반 자세 분류기
/// - 입력: 특징 벡터 (예: 각도/비율 등)
/// - 출력: [누워있음, 앉아있음, 서있음] 확률과 최고 확률 라벨
class PostureTfLiteClassifier {
  Interpreter? _interpreter;
  bool _isAvailable = false;

  // 라벨 순서는 모델 출력 순서와 일치해야 함
  final List<String> _labels = const ['누워있음', '앉아있음', '서있음'];

  bool get isAvailable => _isAvailable && _interpreter != null;

  Future<void> init({String assetPath = 'assets/models/posture_classifier.tflite'}) async {
    try {
      // 자산에 모델이 없을 수도 있으므로 예외를 안전하게 처리
      _interpreter = await Interpreter.fromAsset(assetPath);
      _isAvailable = true;
    } catch (_) {
      // 모델이 없거나 로드 실패 시 비활성화하고 휴리스틱으로 폴백
      _isAvailable = false;
      _interpreter = null;
    }
  }

  /// 특징 벡터로 분류 실행
  /// 반환: {'posture': String, 'confidence': double, 'probs': List<double>}
  Map<String, dynamic> classify(List<double> features) {
    if (!isAvailable) {
      // 간단 휴리스틱 폴백: Provider와 동일한 정규화 피처 전제
      // features = [knee/180, torsoAngle/90, torsoVertDist/200, shoulderHipRatio]
      final double kneeN = features.isNotEmpty ? features[0].clamp(0.0, 1.0) : 0.0;
      final double torsoAngleN = features.length > 1 ? features[1].clamp(0.0, 1.0) : 0.0;
      final double torsoDistN = features.length > 2 ? features[2].clamp(0.0, 1.0) : 0.0;
      final double ratio = features.length > 3 ? features[3].clamp(0.0, 2.0) : 1.0;

      String posture;
      double confidence;
      List<double> probs = [0.33, 0.33, 0.34]; // lie, sit, stand 기본값

      // 누워있음: 몸통 세로거리 작고, 몸통각 작음
      if (torsoDistN < 0.25 && torsoAngleN < 0.33) {
        posture = '누워있음';
        confidence = 0.7;
        probs = [0.7, 0.15, 0.15];
      }
      // 서있음: 무릎이 펴져있고 세로거리 큼
      else if (kneeN > (160.0 / 180.0) && torsoDistN > 0.4) {
        posture = '서있음';
        confidence = 0.7;
        probs = [0.15, 0.15, 0.7];
      }
      // 앉아있음: 무릎 굽힘, 세로거리 어느정도, 몸통각 큼
      else if (kneeN < (140.0 / 180.0) && torsoDistN > 0.2 && torsoAngleN > 0.5) {
        posture = '앉아있음';
        confidence = 0.6;
        probs = [0.15, 0.7, 0.15];
      }
      // 보조 규칙
      else if (ratio > 0.9) {
        posture = '누워있음';
        confidence = 0.5;
        probs = [0.5, 0.25, 0.25];
      } else if (ratio < 0.6 && kneeN > (150.0 / 180.0)) {
        posture = '서있음';
        confidence = 0.5;
        probs = [0.25, 0.25, 0.5];
      } else if (kneeN < (130.0 / 180.0)) {
        posture = '앉아있음';
        confidence = 0.5;
        probs = [0.25, 0.5, 0.25];
      } else {
        posture = '서있음';
        confidence = 0.4;
        probs = [0.2, 0.4, 0.4];
      }

      return {'posture': posture, 'confidence': confidence, 'probs': probs};
    }

    // 입력 텐서 형태 확인 (일반적으로 [1, N])
    final inputShape = _interpreter!.getInputTensor(0).shape;
    final outputShape = _interpreter!.getOutputTensor(0).shape;

    final int numFeatures = inputShape.length == 2 ? inputShape[1] : features.length;
    final int numClasses = outputShape.isNotEmpty ? outputShape.last : _labels.length;

    // 입력 길이 맞추기 (부족하면 0으로 패딩, 길면 잘라냄)
    final inputVector = List<double>.filled(numFeatures, 0.0);
    for (int i = 0; i < min(numFeatures, features.length); i++) {
      inputVector[i] = features[i];
    }

    final input = [inputVector];
    final output = [List<double>.filled(numClasses, 0.0)];

    _interpreter!.run(input, output);

    final probs = output[0];
    int bestIdx = 0;
    double bestVal = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > bestVal) {
        bestVal = probs[i];
        bestIdx = i;
      }
    }

    final posture = bestIdx < _labels.length ? _labels[bestIdx] : '알 수 없음';
    final confidence = bestVal.clamp(0.0, 1.0);

    return {
      'posture': posture,
      'confidence': confidence,
      'probs': probs,
    };
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _isAvailable = false;
  }
}


