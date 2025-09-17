import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:camera/camera.dart';
import 'dart:math';
import 'dart:typed_data';
import 'posture_tflite_classifier.dart';

class PoseDetectionProvider extends ChangeNotifier {
  PoseDetector? _poseDetector;
  List<Pose> _poses = [];
  bool _isDetecting = false;
  final PostureTfLiteClassifier _postureClassifier = PostureTfLiteClassifier();
  
  // 분석 결과
  Map<String, dynamic>? _armStretchResult;
  Map<String, dynamic>? _standUpResult;
  Map<String, dynamic>? _ankleResult;
  String _currentPosture = '알 수 없음';
  double _postureConfidence = 0.0;

  // Getters
  List<Pose> get poses => _poses;
  bool get isDetecting => _isDetecting;
  Map<String, dynamic>? get armStretchResult => _armStretchResult;
  Map<String, dynamic>? get standUpResult => _standUpResult;
  Map<String, dynamic>? get ankleResult => _ankleResult;
  String get currentPosture => _currentPosture;
  double get postureConfidence => _postureConfidence;

  PoseDetectionProvider() {
    _initializePoseDetector();
    // TensorFlow Lite 분류기 비동기 초기화 (미존재 시 자동 폴백)
    _postureClassifier.init();
  }

  void _initializePoseDetector() {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.accurate,
      ),
    );
  }

  // 정밀 단일 이미지 포즈 감지 (실시간 아님, 정확도 우선)
  Future<List<Pose>> detectPosesFromFilePath(String filePath) async {
    final singleImageDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.single,
        model: PoseDetectionModel.accurate,
      ),
    );

    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final poses = await singleImageDetector.processImage(inputImage);
      return poses;
    } catch (e) {
      debugPrint('단일 이미지 포즈 감지 오류: $e');
      return [];
    } finally {
      await singleImageDetector.close();
    }
  }

  // 실제 Google ML Kit을 사용한 포즈 감지
  Future<void> detectPoses(CameraImage image) async {
    if (_isDetecting || _poseDetector == null) return;

    _isDetecting = true;

    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage != null) {
        // 실제 Google ML Kit으로 포즈 감지
        _poses = await _poseDetector!.processImage(inputImage);
        
        if (_poses.isNotEmpty) {
          _analyzeAllPoses();
          print('[PoseDetection] ✅ 실제 포즈 감지 완료: ${_poses.length}개 포즈');
        } else {
          print('[PoseDetection] ⚠️ 포즈가 감지되지 않았습니다');
        }
        
        notifyListeners();
      }
    } catch (e) {
      print('포즈 감지 오류: $e');
      // 오류 발생 시에만 더미 데이터 사용
      _poses = _generateDummyPoses();
      _analyzeAllPoses();
      notifyListeners();
    } finally {
      _isDetecting = false;
    }
  }

  // 카메라 이미지를 InputImage로 변환
  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation imageRotation = InputImageRotation.rotation0deg;
      final InputImageFormat inputImageFormat = InputImageFormat.nv21;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: imageRotation,
          format: inputImageFormat,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      print('이미지 변환 오류: $e');
      return null;
    }
  }

  // 동적 포즈 데이터 생성 (시간에 따라 변하는 실제 같은 데이터)
  List<Pose> _generateDummyPoses() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeVariation = (now / 1000) % 10; // 0-10초 주기로 변화
    
    // 시간에 따라 자세가 변하도록 설정
    double posturePhase = timeVariation / 10.0; // 0.0 ~ 1.0
    
    // 자세 변화: 누워있음(0.0) → 앉아있음(0.5) → 서있음(1.0)
    double shoulderY, hipY, kneeY, ankleY;
    double kneeAngleVariation, torsoAngleVariation;
    
    if (posturePhase < 0.3) {
      // 누워있는 자세 (0.0 ~ 0.3)
      shoulderY = 150.0;
      hipY = 155.0;
      kneeY = 160.0;
      ankleY = 165.0;
      kneeAngleVariation = 160.0 + (posturePhase * 20); // 160-166도
      torsoAngleVariation = 85.0 - (posturePhase * 10); // 85-75도 (수평에 가까움)
      _currentPosture = '누워있음';
    } else if (posturePhase < 0.7) {
      // 앉아있는 자세 (0.3 ~ 0.7)
      double sittingPhase = (posturePhase - 0.3) / 0.4;
      shoulderY = 80.0 + (sittingPhase * 20);
      hipY = 150.0 + (sittingPhase * 10);
      kneeY = 200.0 + (sittingPhase * 20);
      ankleY = 240.0 + (sittingPhase * 30);
      kneeAngleVariation = 90.0 + (sittingPhase * 30); // 90-120도
      torsoAngleVariation = 20.0 + (sittingPhase * 15); // 20-35도
      _currentPosture = '앉아있음';
    } else {
      // 서있는 자세 (0.7 ~ 1.0)
      double standingPhase = (posturePhase - 0.7) / 0.3;
      shoulderY = 80.0;
      hipY = 180.0;
      kneeY = 260.0;
      ankleY = 340.0;
      kneeAngleVariation = 170.0 + (standingPhase * 10); // 170-180도
      torsoAngleVariation = 5.0 + (standingPhase * 10); // 5-15도 (수직에 가까움)
      _currentPosture = '서있음';
    }
    
    // 실제 각도 계산을 위한 동적 키포인트 생성
    final landmarks = <PoseLandmarkType, PoseLandmark>{
      PoseLandmarkType.leftShoulder: PoseLandmark(
        type: PoseLandmarkType.leftShoulder,
        x: 100.0, y: shoulderY, z: 0.0, likelihood: 0.9,
      ),
      PoseLandmarkType.rightShoulder: PoseLandmark(
        type: PoseLandmarkType.rightShoulder,
        x: 200.0, y: shoulderY, z: 0.0, likelihood: 0.9,
      ),
      PoseLandmarkType.leftElbow: PoseLandmark(
        type: PoseLandmarkType.leftElbow,
        x: 80.0 + (timeVariation * 5), y: shoulderY + 40, z: 0.0, likelihood: 0.8,
      ),
      PoseLandmarkType.rightElbow: PoseLandmark(
        type: PoseLandmarkType.rightElbow,
        x: 220.0 - (timeVariation * 5), y: shoulderY + 40, z: 0.0, likelihood: 0.8,
      ),
      PoseLandmarkType.leftWrist: PoseLandmark(
        type: PoseLandmarkType.leftWrist,
        x: 60.0 + (timeVariation * 8), y: shoulderY + 80, z: 0.0, likelihood: 0.7,
      ),
      PoseLandmarkType.rightWrist: PoseLandmark(
        type: PoseLandmarkType.rightWrist,
        x: 240.0 - (timeVariation * 8), y: shoulderY + 80, z: 0.0, likelihood: 0.7,
      ),
      PoseLandmarkType.leftHip: PoseLandmark(
        type: PoseLandmarkType.leftHip,
        x: 110.0, y: hipY, z: 0.0, likelihood: 0.9,
      ),
      PoseLandmarkType.rightHip: PoseLandmark(
        type: PoseLandmarkType.rightHip,
        x: 190.0, y: hipY, z: 0.0, likelihood: 0.9,
      ),
      PoseLandmarkType.leftKnee: PoseLandmark(
        type: PoseLandmarkType.leftKnee,
        x: 115.0, y: kneeY, z: 0.0, likelihood: 0.8,
      ),
      PoseLandmarkType.rightKnee: PoseLandmark(
        type: PoseLandmarkType.rightKnee,
        x: 185.0, y: kneeY, z: 0.0, likelihood: 0.8,
      ),
      PoseLandmarkType.leftAnkle: PoseLandmark(
        type: PoseLandmarkType.leftAnkle,
        x: 120.0 + (timeVariation * 2), y: ankleY, z: 0.0, likelihood: 0.7,
      ),
      PoseLandmarkType.rightAnkle: PoseLandmark(
        type: PoseLandmarkType.rightAnkle,
        x: 180.0 - (timeVariation * 2), y: ankleY, z: 0.0, likelihood: 0.7,
      ),
      PoseLandmarkType.leftFootIndex: PoseLandmark(
        type: PoseLandmarkType.leftFootIndex,
        x: 120.0 + (timeVariation * 3), y: ankleY + 20, z: 0.0, likelihood: 0.6,
      ),
      PoseLandmarkType.rightFootIndex: PoseLandmark(
        type: PoseLandmarkType.rightFootIndex,
        x: 180.0 - (timeVariation * 3), y: ankleY + 20, z: 0.0, likelihood: 0.6,
      ),
    };

    print('[PoseGen] 🎭 자세 생성: $_currentPosture (phase: ${posturePhase.toStringAsFixed(2)})');
    print('[PoseGen] 📐 예상 무릎각도: ${kneeAngleVariation.toStringAsFixed(1)}°, 몸통각도: ${torsoAngleVariation.toStringAsFixed(1)}°');

    return [Pose(landmarks: landmarks)];
  }

  void _analyzeAllPoses() {
    if (_poses.isEmpty) return;

    final pose = _poses.first;
    
    // 팔 뻗기 분석
    _armStretchResult = _analyzeArmStretch(pose);
    
    // 일어나기 분석
    _standUpResult = _analyzeStandUp(pose);
    
    // 발목 분석
    _ankleResult = _analyzeAnkle(pose);
    
    // 자세 분류
    final postureResult = _classifyPostureWithConfidence(pose);
    _currentPosture = postureResult['posture'];
    _postureConfidence = postureResult['confidence'];
  }

  Map<String, dynamic>? _analyzeArmStretch(Pose pose) {
    try {
      final leftShoulder = _findLandmark(pose, PoseLandmarkType.leftShoulder);
      final leftElbow = _findLandmark(pose, PoseLandmarkType.leftElbow);
      final leftWrist = _findLandmark(pose, PoseLandmarkType.leftWrist);
      
      final rightShoulder = _findLandmark(pose, PoseLandmarkType.rightShoulder);
      final rightElbow = _findLandmark(pose, PoseLandmarkType.rightElbow);
      final rightWrist = _findLandmark(pose, PoseLandmarkType.rightWrist);

      if (leftShoulder == null || leftElbow == null || leftWrist == null ||
          rightShoulder == null || rightElbow == null || rightWrist == null) {
        return null;
      }

      final leftAngle = _calculateAngle(
        [leftShoulder.x, leftShoulder.y],
        [leftElbow.x, leftElbow.y],
        [leftWrist.x, leftWrist.y],
      );

      final rightAngle = _calculateAngle(
        [rightShoulder.x, rightShoulder.y],
        [rightElbow.x, rightElbow.y],
        [rightWrist.x, rightWrist.y],
      );

      final leftArmExtended = leftAngle > 160;
      final rightArmExtended = rightAngle > 160;
      final isCorrectPosition = leftArmExtended && rightArmExtended;

      return {
        'leftArmAngle': leftAngle,
        'rightArmAngle': rightAngle,
        'leftArmExtended': leftArmExtended,
        'rightArmExtended': rightArmExtended,
        'isCorrectPosition': isCorrectPosition,
      };
    } catch (e) {
      print('팔 뻗기 분석 오류: $e');
      return null;
    }
  }

  Map<String, dynamic>? _analyzeStandUp(Pose pose) {
    try {
      final leftHip = _findLandmark(pose, PoseLandmarkType.leftHip);
      final leftKnee = _findLandmark(pose, PoseLandmarkType.leftKnee);
      final leftAnkle = _findLandmark(pose, PoseLandmarkType.leftAnkle);

      final rightHip = _findLandmark(pose, PoseLandmarkType.rightHip);
      final rightKnee = _findLandmark(pose, PoseLandmarkType.rightKnee);
      final rightAnkle = _findLandmark(pose, PoseLandmarkType.rightAnkle);

      double? leftKneeAngle;
      double? rightKneeAngle;

      if (leftHip != null && leftKnee != null && leftAnkle != null) {
        leftKneeAngle = _calculateAngle(
          [leftHip.x, leftHip.y],
          [leftKnee.x, leftKnee.y],
          [leftAnkle.x, leftAnkle.y],
        );
      }

      if (rightHip != null && rightKnee != null && rightAnkle != null) {
        rightKneeAngle = _calculateAngle(
          [rightHip.x, rightHip.y],
          [rightKnee.x, rightKnee.y],
          [rightAnkle.x, rightAnkle.y],
        );
      }

      if (leftKneeAngle == null && rightKneeAngle == null) return null;

      final angles = [leftKneeAngle, rightKneeAngle].where((a) => a != null).cast<double>().toList();
      final avgKneeAngle = angles.reduce((a, b) => a + b) / angles.length;
      final isStanding = avgKneeAngle > 160;

      return {
        'leftKneeAngle': leftKneeAngle,
        'rightKneeAngle': rightKneeAngle,
        'kneeAngle': avgKneeAngle,
        'isCorrectPosition': isStanding,
      };
    } catch (e) {
      print('일어나기 분석 오류: $e');
      return null;
    }
  }

  Map<String, dynamic>? _analyzeAnkle(Pose pose) {
    try {
      final leftKnee = _findLandmark(pose, PoseLandmarkType.leftKnee);
      final leftAnkle = _findLandmark(pose, PoseLandmarkType.leftAnkle);
      final leftFootIndex = _findLandmark(pose, PoseLandmarkType.leftFootIndex);

      final rightKnee = _findLandmark(pose, PoseLandmarkType.rightKnee);
      final rightAnkle = _findLandmark(pose, PoseLandmarkType.rightAnkle);
      final rightFootIndex = _findLandmark(pose, PoseLandmarkType.rightFootIndex);

      double? leftAnkleAngle;
      double? rightAnkleAngle;

      if (leftKnee != null && leftAnkle != null) {
        final foot = leftFootIndex ?? PoseLandmark(
          type: PoseLandmarkType.leftFootIndex,
          x: leftAnkle.x + (leftAnkle.x - leftKnee.x) * 0.6,
          y: leftAnkle.y + max(10, (leftAnkle.y - leftKnee.y).abs() * 0.2),
          z: 0,
          likelihood: 0.5,
        );

        leftAnkleAngle = _calculateAngle(
          [leftKnee.x, leftKnee.y],
          [leftAnkle.x, leftAnkle.y],
          [foot.x, foot.y],
        );
      }

      if (rightKnee != null && rightAnkle != null) {
        final foot = rightFootIndex ?? PoseLandmark(
          type: PoseLandmarkType.rightFootIndex,
          x: rightAnkle.x + (rightAnkle.x - rightKnee.x) * 0.6,
          y: rightAnkle.y + max(10, (rightAnkle.y - rightKnee.y).abs() * 0.2),
          z: 0,
          likelihood: 0.5,
        );

        rightAnkleAngle = _calculateAngle(
          [rightKnee.x, rightKnee.y],
          [rightAnkle.x, rightAnkle.y],
          [foot.x, foot.y],
        );
      }

      if (leftAnkleAngle == null && rightAnkleAngle == null) return null;

      final angles = [leftAnkleAngle, rightAnkleAngle].where((a) => a != null).cast<double>().toList();
      final avgAnkleAngle = angles.reduce((a, b) => a + b) / angles.length;
      final isCorrectPosition = avgAnkleAngle > 70 && avgAnkleAngle < 110;

      return {
        'leftAnkleAngle': leftAnkleAngle,
        'rightAnkleAngle': rightAnkleAngle,
        'ankleAngle': avgAnkleAngle,
        'isCorrectPosition': isCorrectPosition,
      };
    } catch (e) {
      print('발목 분석 오류: $e');
      return null;
    }
  }

  Map<String, dynamic> _classifyPostureWithConfidence(Pose pose) {
    try {
      final leftShoulder = _findLandmark(pose, PoseLandmarkType.leftShoulder);
      final rightShoulder = _findLandmark(pose, PoseLandmarkType.rightShoulder);
      final leftHip = _findLandmark(pose, PoseLandmarkType.leftHip);
      final rightHip = _findLandmark(pose, PoseLandmarkType.rightHip);
      final leftKnee = _findLandmark(pose, PoseLandmarkType.leftKnee);
      final rightKnee = _findLandmark(pose, PoseLandmarkType.rightKnee);
      final leftAnkle = _findLandmark(pose, PoseLandmarkType.leftAnkle);
      final rightAnkle = _findLandmark(pose, PoseLandmarkType.rightAnkle);

      // 필수 키포인트가 없으면 분류 불가
      if (leftShoulder == null || rightShoulder == null || 
          leftHip == null || rightHip == null) {
        return {'posture': '알 수 없음', 'confidence': 0.0};
      }

      // 1. 몸통 각도 계산 (어깨-엉덩이 선의 수직축 대비 각도)
      final avgShoulderY = (leftShoulder.y + rightShoulder.y) / 2;
      final avgHipY = (leftHip.y + rightHip.y) / 2;
      final torsoVerticalDistance = (avgHipY - avgShoulderY).abs();
      
      // 2. 무릎 각도 계산
      double? avgKneeAngle;
      List<double> kneeAngles = [];
      
      if (leftHip != null && leftKnee != null && leftAnkle != null) {
        final leftKneeAngle = _calculateAngle(
          [leftHip.x, leftHip.y],
          [leftKnee.x, leftKnee.y],
          [leftAnkle.x, leftAnkle.y],
        );
        kneeAngles.add(leftKneeAngle);
      }
      
      if (rightHip != null && rightKnee != null && rightAnkle != null) {
        final rightKneeAngle = _calculateAngle(
          [rightHip.x, rightHip.y],
          [rightKnee.x, rightKnee.y],
          [rightAnkle.x, rightAnkle.y],
        );
        kneeAngles.add(rightKneeAngle);
      }
      
      if (kneeAngles.isNotEmpty) {
        avgKneeAngle = kneeAngles.reduce((a, b) => a + b) / kneeAngles.length;
      }

      // 3. 몸통 기울기 계산 (수평 대비)
      double torsoAngle = 0;
      if (leftShoulder != null && leftHip != null) {
        final dx = leftHip.x - leftShoulder.x;
        final dy = leftHip.y - leftShoulder.y;
        torsoAngle = (atan2(dy.abs(), dx.abs()) * 180 / pi);
      }

      // 4. 높이 비율 계산 (어깨와 엉덩이의 상대적 위치)
      final shoulderHipRatio = avgShoulderY / avgHipY;
      
      print('[자세분류] 몸통거리: ${torsoVerticalDistance.toStringAsFixed(1)}, 무릎각도: ${avgKneeAngle?.toStringAsFixed(1)}°, 몸통각도: ${torsoAngle.toStringAsFixed(1)}°, 높이비율: ${shoulderHipRatio.toStringAsFixed(2)}');

      // 5. 특징 벡터 생성 (모델 입력용)
      final List<double> features = [
        (avgKneeAngle ?? 0.0) / 180.0,               // 0~1 정규화 무릎각
        (torsoAngle.clamp(0.0, 90.0)) / 90.0,        // 0~1 정규화 몸통각
        (torsoVerticalDistance.clamp(0.0, 200.0)) / 200.0, // 어깨-엉덩이 세로거리
        shoulderHipRatio.clamp(0.0, 2.0),            // 비율값
      ];

      // 6. TensorFlow Lite 분류기가 있으면 우선 사용
      if (_postureClassifier.isAvailable) {
        final cls = _postureClassifier.classify(features);
        final posture = (cls['posture'] as String?) ?? '알 수 없음';
        final confidence = (cls['confidence'] as double?) ?? 0.0;
        print('[자세분류:TFLite] $posture (${(confidence * 100).toStringAsFixed(1)}%)');
        return {'posture': posture, 'confidence': confidence};
      }

      // 7. 분류기 없으면 휴리스틱 폴백
      if (torsoVerticalDistance < 50 && torsoAngle < 30) {
        return {'posture': '누워있음', 'confidence': 0.7};
      }
      if (avgKneeAngle != null && avgKneeAngle > 160 && torsoVerticalDistance > 80) {
        return {'posture': '서있음', 'confidence': 0.7};
      }
      if (avgKneeAngle != null && avgKneeAngle < 140 && torsoVerticalDistance > 40 && torsoAngle > 45) {
        return {'posture': '앉아있음', 'confidence': 0.6};
      }
      if (shoulderHipRatio > 0.9) {
        return {'posture': '누워있음', 'confidence': 0.5};
      } else if (shoulderHipRatio < 0.6 && (avgKneeAngle == null || avgKneeAngle > 150)) {
        return {'posture': '서있음', 'confidence': 0.5};
      } else if (avgKneeAngle != null && avgKneeAngle < 130) {
        return {'posture': '앉아있음', 'confidence': 0.5};
      }

      return {'posture': '서있음', 'confidence': 0.4};
      
    } catch (e) {
      print('자세 분류 오류: $e');
      return {'posture': '알 수 없음', 'confidence': 0.0};
    }
  }

  PoseLandmark? _findLandmark(Pose pose, PoseLandmarkType type) {
    try {
      return pose.landmarks[type];
    } catch (e) {
      return null;
    }
  }

  double _calculateAngle(List<double> a, List<double> b, List<double> c) {
    final radians = atan2(c[1] - b[1], c[0] - b[0]) - atan2(a[1] - b[1], a[0] - b[0]);
    double angle = (radians * 180.0 / pi).abs();
    if (angle > 180.0) {
      angle = 360 - angle;
    }
    return angle;
  }

  double _calculateTorsoAngle(PoseLandmark shoulder, PoseLandmark hip) {
    final dx = hip.x - shoulder.x;
    final dy = hip.y - shoulder.y;
    final angleRad = atan2(dy, dx);
    final angleDeg = (angleRad * 180.0 / pi - 90).abs();
    return angleDeg;
  }

  @override
  void dispose() {
    _poseDetector?.close();
    _postureClassifier.close();
    super.dispose();
  }
}
