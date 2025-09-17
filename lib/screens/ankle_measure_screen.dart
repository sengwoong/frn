import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'dart:io';
import '../main.dart';
import 'pose_detection_screen.dart';

class Point {
  final double x;
  final double y;
  final int id;

  Point({required this.x, required this.y, required this.id});
}

class AnkleMeasureScreen extends StatefulWidget {
  @override
  _AnkleMeasureScreenState createState() => _AnkleMeasureScreenState();
}

class _AnkleMeasureScreenState extends State<AnkleMeasureScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  
  // 사진 기반 측정
  String? _capturedPhotoPath;
  List<Point> _points = [];
  double? _calculatedAngle;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (cameras.isEmpty) {
      _showSnackBar('카메라를 찾을 수 없습니다.');
      return;
    }

    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      _showSnackBar('카메라 권한이 필요합니다.');
      return;
    }

    // 후면 카메라 찾기 (발목 측정용)
    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    
    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      setState(() {
        _isCameraInitialized = true;
      });

      print('[AngleMeasure] 📸 카메라 초기화 완료');
    } catch (e) {
      print('카메라 초기화 오류: $e');
      _showSnackBar('카메라 초기화에 실패했습니다.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // 사진 촬영
  Future<void> _takePicture() async {
    if (_cameraController == null || _isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final photo = await _cameraController!.takePicture();
          setState(() {
        _capturedPhotoPath = photo.path;
        _points.clear(); // 새 사진이면 점들 초기화
        _calculatedAngle = null;
      });
      
      print('[AngleMeasure] 📸 사진 촬영 완료: ${photo.path}');
    } catch (error) {
      print('[AngleMeasure] ❌ 사진 촬영 실패: $error');
      _showSnackBar('사진 촬영에 실패했습니다.');
    }

    setState(() {
      _isCapturing = false;
    });
  }

  // 사진에서 점 클릭 처리
  void _onPhotoTap(TapUpDetails details) {
    print('[AngleMeasure] 터치 감지됨! 현재 점 개수: ${_points.length}');
    
    if (_capturedPhotoPath == null) {
      print('[AngleMeasure] ❌ 사진이 없음');
      return;
    }
    
    if (_points.length >= 3) {
      print('[AngleMeasure] ❌ 이미 3개 점이 있음');
      return;
    }

    final newPoint = Point(
      x: details.localPosition.dx,
      y: details.localPosition.dy,
      id: _points.length + 1,
    );

    print('[AngleMeasure] 새 점 생성: ID=${newPoint.id}, 위치=(${newPoint.x.toStringAsFixed(1)}, ${newPoint.y.toStringAsFixed(1)})');

    setState(() {
      _points.add(newPoint);
      print('[AngleMeasure] setState 완료. 총 점 개수: ${_points.length}');
    });

    print('[AngleMeasure] ✅ 점 ${_points.length} 추가 완료');
    
    // 각 점의 색상 확인
    for (int i = 0; i < _points.length; i++) {
      final color = _getPointColor(_points[i].id);
      print('[AngleMeasure] 점 ${_points[i].id}: 색상=$color');
    }

    // 3개 점이 모두 찍히면 각도 계산
    if (_points.length == 3) {
      print('[AngleMeasure] 🎯 3개 점 완료! 각도 계산 시작');
      Future.delayed(Duration(milliseconds: 100), () {
        _calculateAngleFromPoints();
      });
    }
  }

  // 3점으로 각도 계산
  void _calculateAngleFromPoints() {
    if (_points.length != 3) return;

    final p1 = _points[0];
    final p2 = _points[1]; // 중심점 (각도의 꼭짓점)
    final p3 = _points[2];

    // 벡터 계산
    final vector1 = [p1.x - p2.x, p1.y - p2.y];
    final vector2 = [p3.x - p2.x, p3.y - p2.y];

    // 벡터의 내적
    final dotProduct = vector1[0] * vector2[0] + vector1[1] * vector2[1];

    // 벡터의 크기
    final magnitude1 = sqrt(vector1[0] * vector1[0] + vector1[1] * vector1[1]);
    final magnitude2 = sqrt(vector2[0] * vector2[0] + vector2[1] * vector2[1]);

    if (magnitude1 == 0 || magnitude2 == 0) return;

    // 코사인 값
    final cosAngle = dotProduct / (magnitude1 * magnitude2);

    // 각도 계산 (라디안 → 도)
    final angleInRadians = acos(cosAngle.clamp(-1.0, 1.0));
    final angleInDegrees = (angleInRadians * 180.0) / pi;

    setState(() {
      _calculatedAngle = angleInDegrees;
    });

    print('[AngleMeasure] 🎯 계산된 각도: ${angleInDegrees.toStringAsFixed(2)}°');

    // 결과 표시
    _showDialog(
      '각도 측정 완료',
      '측정된 각도: ${angleInDegrees.toStringAsFixed(2)}°\n\n점 1: (${p1.x.toStringAsFixed(0)}, ${p1.y.toStringAsFixed(0)})\n점 2 (중심): (${p2.x.toStringAsFixed(0)}, ${p2.y.toStringAsFixed(0)})\n점 3: (${p3.x.toStringAsFixed(0)}, ${p3.y.toStringAsFixed(0)})',
    );
  }

  // 새 사진 촬영
  void _retakePhoto() {
    setState(() {
      _capturedPhotoPath = null;
      _points.clear();
      _calculatedAngle = null;
    });
    print('[AngleMeasure] 🔄 새 사진 촬영 모드');
  }

  // 점 초기화
  void _resetPoints() {
    setState(() {
      _points.clear();
      _calculatedAngle = null;
    });
    print('[AngleMeasure] 🔄 점 초기화 완료. 점 개수: ${_points.length}');
  }

  // 강제 점 추가 (디버그용)
  void _addTestPoint() {
    if (_points.length >= 3) return;
    
    final testPoint = Point(
      x: 100.0 + (_points.length * 50.0),
      y: 100.0 + (_points.length * 50.0),
      id: _points.length + 1,
    );
    
    setState(() {
      _points.add(testPoint);
    });
    
    print('[AngleMeasure] 🧪 테스트 점 추가: ${_points.length}/3');
  }

  // 점 색상 가져오기
  Color _getPointColor(int pointId) {
    switch (pointId) {
      case 1:
        return Colors.red; // 빨간색 - 첫 번째 점
      case 2:
        return Colors.blue; // 파란색 - 중심점 (각도의 꼭짓점)
      case 3:
        return Colors.green; // 초록색 - 세 번째 점
      default:
        return Colors.white;
    }
  }

  // 안내 텍스트 가져오기
  String _getInstructionText() {
    if (_capturedPhotoPath == null) {
      return '📸 먼저 사진을 촬영하세요';
    } else if (_points.length == 0) {
      return '1단계: 첫 번째 점을 터치하세요 (예: 무릎)';
    } else if (_points.length == 1) {
      return '2단계: 두 번째 점(각도의 중심)을 터치하세요 (예: 발목)';
    } else if (_points.length == 2) {
      return '3단계: 세 번째 점을 터치하세요 (예: 발끝)';
    } else {
      return '측정 완료! 각도: ${_calculatedAngle?.toStringAsFixed(2)}°';
    }
  }

  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              child: Text('다시 측정'),
              onPressed: () {
                Navigator.of(context).pop();
                _resetPoints();
              },
            ),
            TextButton(
              child: Text('새 사진'),
              onPressed: () {
                Navigator.of(context).pop();
                _retakePhoto();
              },
            ),
            TextButton(
              child: Text('확인'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 헤더
            Container(
              padding: EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      '← 뒤로',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  Text(
                    '발목 각도 측정',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _resetPoints,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '초기화',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PoseDetectionScreen(detectionType: 'standup'),
                            ),
                          );
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '건너뛰기',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 안내 메시지
            Container(
              padding: EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                              children: [
                                Text(
                    _getInstructionText(),
                                  style: TextStyle(
                      fontSize: 16,
                                    fontWeight: FontWeight.bold,
                      color: Colors.black,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                  SizedBox(height: 4),
                                  Text(
                    _capturedPhotoPath == null
                        ? '사진을 촬영한 후 점 3개를 찍어서 각도를 측정하세요'
                        : '사진에서 점 3개를 터치하면 각도가 자동으로 계산됩니다',
                                    style: TextStyle(
                                      fontSize: 12,
                      color: Colors.grey[600],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
              ),
            ),

            // 카메라/사진 영역
            Expanded(
              child: _isCameraInitialized
                  ? Stack(
                      children: [
                        if (_capturedPhotoPath == null)
                          // 실시간 카메라 (촬영 전)
                          CameraPreview(_cameraController!)
                        else
                          // 촬영된 사진 (측정 모드)
                          Container(
                            width: double.infinity,
                            height: double.infinity,
                            child: Stack(
                              children: [
                                Image.file(
                                  File(_capturedPhotoPath!),
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                                Positioned.fill(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: _onPhotoTap,
                                    onTap: () {
                                      print('[AngleMeasure] onTap 호출됨');
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      color: Colors.transparent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // 찍힌 점들 표시 (터치 방해 않도록 무시)
                        if (_capturedPhotoPath != null) ...[
                          IgnorePointer(
                            ignoring: true,
                            child: Stack(
                              children: [
                                ..._points.map((point) => Positioned(
                                      left: point.x - 15,
                                      top: point.y - 15,
                                      child: Container(
                                        width: 30,
                                        height: 30,
                                        decoration: BoxDecoration(
                                          color: _getPointColor(point.id),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.3),
                                              blurRadius: 4,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text(
                                            point.id.toString(),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )),

                                // 선 그리기 (2개 이상 점이 있을 때)
                                if (_points.length >= 2)
                                  CustomPaint(
                                    size: Size.infinite,
                                    painter: LinePainter(_points),
                                  ),
                              ],
                            ),
                          ),

                          // 상태 표시
                          Positioned(
                            top: 20,
                            right: 20,
                            child: Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '점: ${_points.length}/3',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    )
                  : Center(
                                                child: Text(
                        '카메라 권한이 필요합니다',
                                                  style: TextStyle(
                                                    color: Colors.white,
                          fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ),

            // 하단 버튼 영역
            Container(
              padding: EdgeInsets.all(16),
                                                    color: Colors.white,
              child: Column(
                children: [
                  if (_capturedPhotoPath == null)
                    // 사진 촬영 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isCapturing ? null : _takePicture,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                                                child: Text(
                          _isCapturing ? '📸 촬영 중...' : '📸 사진 촬영',
                                                  style: TextStyle(
                                                    color: Colors.white,
                            fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                    )
                  else
                    // 측정 모드 버튼들
                    Row(
                                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _retakePhoto,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: EdgeInsets.all(12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                                                          child: Text(
                              '📸 새 사진',
                                                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _resetPoints,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: EdgeInsets.all(12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              '🔄 초기화',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PoseDetectionScreen(detectionType: 'standup'),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: EdgeInsets.all(12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              '다음',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                                                  ],
                                                    ),
                                                  ],
                                                ),
            ),

            // 결과 표시
            if (_calculatedAngle != null)
              Container(
                padding: EdgeInsets.all(20),
                color: Colors.white,
                child: Column(
                                                          children: [
                                                            Text(
                      '측정 결과',
                                                              style: TextStyle(
                        fontSize: 16,
                                                                fontWeight: FontWeight.bold,
                        color: Colors.black,
                                                              ),
                                                            ),
                    SizedBox(height: 8),
                                                            Text(
                      '${_calculatedAngle!.toStringAsFixed(2)}°',
                                                              style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    SizedBox(height: 8),
                    Column(
                      children: _points.map((point) {
                        String label = point.id == 1
                            ? '점 1'
                            : point.id == 2
                                ? '점 2 (중심)'
                                : '점 3';
                                                        return Text(
                          '$label: (${point.x.toStringAsFixed(0)}, ${point.y.toStringAsFixed(0)})',
                                                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                                                          ),
                                                        );
                      }).toList(),
                                                  ),
                                              ],
                                          ),
                                        ),
                                      ],
                            ),
                          ),
                        );
  }
}

// 선을 그리기 위한 CustomPainter
class LinePainter extends CustomPainter {
  final List<Point> points;

  LinePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // 점1 -> 점2 선
    if (points.length >= 2) {
      canvas.drawLine(
        Offset(points[0].x, points[0].y),
        Offset(points[1].x, points[1].y),
        paint,
      );
    }

    // 점2 -> 점3 선
    if (points.length >= 3) {
      canvas.drawLine(
        Offset(points[1].x, points[1].y),
        Offset(points[2].x, points[2].y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}