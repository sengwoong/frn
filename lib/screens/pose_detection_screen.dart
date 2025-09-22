import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math' as math;
import '../providers/pose_detection_provider.dart';
import '../main.dart';

class PoseDetectionScreen extends StatefulWidget {
  final String detectionType;

  const PoseDetectionScreen({
    Key? key,
    required this.detectionType,
  }) : super(key: key);

  @override
  _PoseDetectionScreenState createState() => _PoseDetectionScreenState();
}

class _PoseDetectionScreenState extends State<PoseDetectionScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isAnalyzing = false;
  Size? _lastImageSize; // camera image size (w,h) before rotation swap
  InputImageRotation _lastRotation = InputImageRotation.rotation0deg;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('카메라를 찾을 수 없습니다.')),
      );
      return;
    }

    // 카메라 권한 요청
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('카메라 권한이 필요합니다.')),
      );
      return;
    }

    // 전면 카메라 찾기
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    
    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );


// =========================
// Rotation 보정 함수
// =========================
InputImageRotation _rotationFromCamera(CameraDescription camera, DeviceOrientation orientation) {
  int orientationDegrees;
  switch (orientation) {
    case DeviceOrientation.portraitUp:
      orientationDegrees = 0;
      break;
    case DeviceOrientation.landscapeLeft:
      orientationDegrees = 90;
      break;
    case DeviceOrientation.portraitDown:
      orientationDegrees = 180;
      break;
    case DeviceOrientation.landscapeRight:
      orientationDegrees = 270;
      break;
    default:
      orientationDegrees = 0;
  }

  int rotationCompensation;
  if (camera.lensDirection == CameraLensDirection.front) {
    rotationCompensation = (camera.sensorOrientation + orientationDegrees) % 360;
  } else {
    rotationCompensation = (camera.sensorOrientation - orientationDegrees + 360) % 360;
  }

  print("📸 DeviceOrientation: $orientation / "
        "SensorOrientation: ${camera.sensorOrientation} / "
        "RotationCompensation: $rotationCompensation°");

  switch (rotationCompensation) {
    case 0:
      return InputImageRotation.rotation0deg;
    case 90:
      return InputImageRotation.rotation90deg;
    case 180:
      return InputImageRotation.rotation180deg;
    case 270:
      return InputImageRotation.rotation270deg;
    default:
      return InputImageRotation.rotation0deg;
  }
}



    try {
      await _cameraController!.initialize();
      setState(() {
        _isCameraInitialized = true;
      });

      // 이미지 스트림 시작
    
        _cameraController!.startImageStream((CameraImage image) {
  if (!_isAnalyzing) {
    _isAnalyzing = true;

    final rotation = _rotationFromCamera(
      _cameraController!.description,
      _cameraController!.value.deviceOrientation,
    );

    _lastRotation = rotation;
    _lastImageSize = Size(image.width.toDouble(), image.height.toDouble());

    print("🎯 최종 rotation: $_lastRotation, "
          "Image Size: $_lastImageSize");

    context.read<PoseDetectionProvider>().detectPoses(image, rotation).then((_) {
      _isAnalyzing = false;
    });
  }
});
    } catch (e) {
      print('카메라 초기화 오류: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('카메라 초기화에 실패했습니다.')),
      );
    }
  }

  @override
  void dispose() {
    try {
      if (_cameraController != null) {
        if (_cameraController!.value.isStreamingImages) {
          _cameraController!.stopImageStream();
        }
        _cameraController!.dispose();
      }
    } catch (_) {}
    super.dispose();
  }

  String _getTitle() {
    switch (widget.detectionType) {
      case 'standup':
        return '일어나기 측정';
      case 'armstretch':
        return '팔 뻗기 측정';
      case 'ankle':
        return '발목 각도 측정';
      default:
        return '포즈 측정';
    }
  }

  String _getInstructions() {
    switch (widget.detectionType) {
      case 'standup':
        return '전신이 보이도록 촬영해주세요\n누워있음 → 앉아있음 → 서있음 순서로 측정됩니다';
      case 'armstretch':
        return '정면을 보고 양팔을 수평으로 뻗어주세요';
      case 'ankle':
        return '측면에서 발목이 잘 보이도록 촬영해주세요';
      default:
        return '화면의 안내에 따라 자세를 취해주세요';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_getTitle()),
        backgroundColor: Color(0xFF003A56),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 카메라 뷰
          Expanded(
            flex: 3,
            child: _isCameraInitialized
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final previewW = constraints.maxWidth;
                      final previewH = constraints.maxHeight;
                      // 카메라가 회전되면 width/height가 뒤바뀌므로 보정
                      Size? imageSize = _lastImageSize ?? _cameraController!.value.previewSize;
                      if (imageSize != null) {
                        final rot = _lastRotation;
                        final needsSwap = rot == InputImageRotation.rotation90deg || rot == InputImageRotation.rotation270deg;
                        if (needsSwap) {
                          imageSize = Size(imageSize.height, imageSize.width);
                        }
                      }
                      final isFront = _cameraController!.description.lensDirection == CameraLensDirection.front;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(_cameraController!),
                          Consumer<PoseDetectionProvider>(
                            builder: (context, provider, _) {
                              return CustomPaint(
                                painter: _PosePainter(
                                  poses: provider.poses,
                                  imageSize: imageSize,
                                  previewSize: Size(previewW, previewH),
                                  isFrontCamera: isFront,
                                ),
                              );
                            },
                          ),
                          Positioned(
                            top: 12,
                            right: 12,
                            child: _buildStatusDotOverlay(context),
                          ),
                        ],
                      );
                    },
                  )
                : Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
          ),

          // 결과 표시 영역
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: Colors.white,
              child: Consumer<PoseDetectionProvider>(
                builder: (context, provider, child) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 안내 메시지
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _getInstructions(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue[800],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(height: 16),

                        // 현재 자세 (실시간 업데이트)
                        _buildResultCard(
                          '현재 자세',
                          provider.postureConfidence > 0
                              ? '${provider.currentPosture} (${(provider.postureConfidence * 100).toStringAsFixed(0)}%)'
                              : provider.currentPosture,
                          Icons.accessibility_new,
                          _getPostureColor(provider.currentPosture),
                        ),
                        if (provider.postureConfidence > 0) ...[
                          SizedBox(height: 8),
                          _buildConfidenceBar(provider.postureConfidence),
                        ],
                        SizedBox(height: 12),

                        // 감지된 포즈 수
                        _buildResultCard(
                          '감지된 포즈',
                          '${provider.poses.length}개',
                          Icons.person,
                          Colors.blue,
                        ),
                        SizedBox(height: 12),
                        // 좌우 발목 각도 표시
                        _buildResultCard(
                          '왼쪽 발목 각도',
                          () {
                            final a = provider.ankleResult?['leftAnkleAngle'] as num?;
                            if (a == null) return 'N/A';
                            final clamped = a.clamp(0, 120);
                            final folded = (clamped / 90.0).toDouble().clamp(0.0, 1.0);
                            final pct = (math.pow(folded, 2) * 100).clamp(0, 100).round();
                            return '${a.toStringAsFixed(1)}°  (${pct}%)';
                          }(),
                          Icons.rotate_left,
                          Colors.teal,
                        ),
                        SizedBox(height: 8),
                        _buildResultCard(
                          '오른쪽 발목 각도',
                          () {
                            final a = provider.ankleResult?['rightAnkleAngle'] as num?;
                            if (a == null) return 'N/A';
                            final clamped = a.clamp(0, 120);
                            final folded = (clamped / 90.0).toDouble().clamp(0.0, 1.0);
                            final pct = (math.pow(folded, 2) * 100).clamp(0, 100).round();
                            return '${a.toStringAsFixed(1)}°  (${pct}%)';
                          }(),
                          Icons.rotate_right,
                          Colors.teal,
                        ),
                        SizedBox(height: 12),

                        // 타입별 상세 결과
                        _buildDetailedResults(provider),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDotOverlay(BuildContext context) {
    final provider = context.watch<PoseDetectionProvider>();
    final posture = provider.currentPosture; // '앉아있음' | '서있음' | 기타
    final bool isWalk = posture == '걷고있음';
    final bool isSit = posture == '앉아있음';
    final bool isStand = posture == '서있음';
    final Color dotColor = isWalk
        ? Colors.blue
        : (isSit
            ? Colors.orange
            : (isStand ? Colors.green : Colors.grey));

    return Container(
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8),
          Text(
            isWalk
                ? '걷고있음'
                : (isSit
                    ? '앉아있음'
                    : (isStand ? '서있음' : '측정중')),
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }


  Widget _buildResultCard(String title, String value, IconData icon, [Color? iconColor]) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? Color(0xFF003A56)),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceBar(double confidence) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '신뢰도',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              Text(
                '${(confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: Colors.grey[800], fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: confidence.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey[300],
              color: _getPostureColor(context.read<PoseDetectionProvider>().currentPosture),
            ),
          ),
        ],
      ),
    );
  }

  Color _getPostureColor(String posture) {
    switch (posture) {
      case '누워있음':
        return Colors.red;
      case '앉아있음':
        return Colors.orange;
      case '걷고있음':
        return Colors.blue;
      case '서있음':
        return Colors.green;
      default:
        return Color(0xFF003A56);
    }
  }

  Widget _buildDetailedResults(PoseDetectionProvider provider) {
    switch (widget.detectionType) {
      case 'standup':
        return _buildStandUpResults(provider.standUpResult);
      case 'armstretch':
        return _buildArmStretchResults(provider.armStretchResult);
      case 'ankle':
        return _buildAnkleResults(provider.ankleResult);
      default:
        return Container();
    }
  }

  Widget _buildStandUpResults(Map<String, dynamic>? result) {
    if (result == null) {
      return _buildNoDataCard('일어나기 데이터');
    }

    return Column(
      children: [
        _buildResultCard(
          '무릎 각도',
          '${result['kneeAngle']?.toStringAsFixed(1) ?? 'N/A'}°',
          Icons.accessibility,
        ),
        SizedBox(height: 8),
        _buildResultCard(
          '자세 상태',
          result['isCorrectPosition'] ? '서있음 ✅' : '앉아있음/누워있음 ⚠️',
          Icons.check_circle,
        ),
      ],
    );
  }

  Widget _buildArmStretchResults(Map<String, dynamic>? result) {
    if (result == null) {
      return _buildNoDataCard('팔 뻗기 데이터');
    }

    return Column(
      children: [
        _buildResultCard(
          '왼팔 각도',
          '${result['leftArmAngle']?.toStringAsFixed(1) ?? 'N/A'}°',
          Icons.accessibility,
        ),
        SizedBox(height: 8),
        _buildResultCard(
          '오른팔 각도',
          '${result['rightArmAngle']?.toStringAsFixed(1) ?? 'N/A'}°',
          Icons.accessibility,
        ),
        SizedBox(height: 8),
        _buildResultCard(
          '자세 상태',
          result['isCorrectPosition'] ? '올바름 ✅' : '교정 필요 ⚠️',
          Icons.check_circle,
        ),
      ],
    );
  }

  Widget _buildAnkleResults(Map<String, dynamic>? result) {
    if (result == null) {
      return _buildNoDataCard('발목 각도 데이터');
    }

    String _percentFromAngle(num? angleDeg) {
      if (angleDeg == null) return 'N/A';
      // 기준: 0° = 완전 펴짐(0%), 90° = 많이 굽힘(100%)
      final clamped = angleDeg.clamp(0, 120); // 안전 상한
      final normalized = (clamped / 90.0).toDouble();
      final folded = normalized.clamp(0.0, 1.0);
      final curved = math.pow(folded, 2); // 제곱으로 굽힘 강조
      final pct = (curved * 100).clamp(0, 100).round();
      return '$pct%';
    }

    return Column(
      children: [
        _buildResultCard(
          '발목 각도',
          () {
            final angle = result['ankleAngle'] as num?;
            final angleText = angle == null ? 'N/A' : '${angle.toStringAsFixed(1)}°';
            final pct = _percentFromAngle(angle);
            return '$angleText  ($pct)';
          }(),
          Icons.accessibility,
        ),
        SizedBox(height: 8),
        _buildResultCard(
          '유연성 상태',
          result['isCorrectPosition'] ? '정상 범위 ✅' : '비정상 범위 ⚠️',
          Icons.check_circle,
        ),
      ],
    );
  }

  Widget _buildNoDataCard(String dataType) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(Icons.info_outline, color: Colors.grey[600]),
          SizedBox(height: 8),
          Text(
            '$dataType를 감지하는 중...',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// =========================
// Pose overlay painter
// =========================
class _PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size? imageSize; // camera image size
  final Size previewSize; // widget size
  final bool isFrontCamera;

  _PosePainter({
    required this.poses,
    required this.imageSize,
    required this.previewSize,
    required this.isFrontCamera,
  });

  static const List<List<PoseLandmarkType>> connections = [
    // torso
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    // arms
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    // legs
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == null) return;
    final double scaleX = previewSize.width / imageSize!.width;
    final double scaleY = previewSize.height / imageSize!.height;

    final pointPaint = Paint()
      ..color = const Color(0xFF00E1FF)
      ..style = PaintingStyle.fill;
    final hipPaint = Paint()
      ..color = const Color(0xFFFFD166)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final pose in poses) {
      final lm = pose.landmarks;

      // draw connections
      for (final pair in connections) {
        final a = lm[pair.first];
        final b = lm[pair.last];
        if (a == null || b == null) continue;
        final pa = _map(a.x, a.y, scaleX, scaleY);
        final pb = _map(b.x, b.y, scaleX, scaleY);
        canvas.drawLine(pa, pb, linePaint);
      }

      // draw all keypoints
      for (final entry in lm.entries) {
        final p = _map(entry.value.x, entry.value.y, scaleX, scaleY);
        final isHip = entry.key == PoseLandmarkType.leftHip || entry.key == PoseLandmarkType.rightHip;
        canvas.drawCircle(p, isHip ? 5 : 3.5, isHip ? hipPaint : pointPaint);
      }

      // waist midpoint
      final leftHip = lm[PoseLandmarkType.leftHip];
      final rightHip = lm[PoseLandmarkType.rightHip];
      if (leftHip != null && rightHip != null) {
        final lp = _map(leftHip.x, leftHip.y, scaleX, scaleY);
        final rp = _map(rightHip.x, rightHip.y, scaleX, scaleY);
        final mid = Offset((lp.dx + rp.dx) / 2, (lp.dy + rp.dy) / 2);
        canvas.drawCircle(mid, 6, hipPaint);
      }
    }
  }

  Offset _map(double x, double y, double scaleX, double scaleY) {
    double mappedX = x * scaleX;
    final double mappedY = y * scaleY;
    if (isFrontCamera) {
      mappedX = previewSize.width - mappedX; // mirror horizontally for front camera
    }
    return Offset(mappedX, mappedY);
  }

  @override
  bool shouldRepaint(covariant _PosePainter oldDelegate) {
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.previewSize != previewSize ||
        oldDelegate.isFrontCamera != isFrontCamera;
  }
}
