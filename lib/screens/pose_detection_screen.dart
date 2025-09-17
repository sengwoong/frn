import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
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

    try {
      await _cameraController!.initialize();
      setState(() {
        _isCameraInitialized = true;
      });

      // 이미지 스트림 시작
      _cameraController!.startImageStream((CameraImage image) {
        if (!_isAnalyzing) {
          _isAnalyzing = true;
          context.read<PoseDetectionProvider>().detectPoses(image).then((_) {
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
    _cameraController?.dispose();
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
                ? CameraPreview(_cameraController!)
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

    return Column(
      children: [
        _buildResultCard(
          '발목 각도',
          '${result['ankleAngle']?.toStringAsFixed(1) ?? 'N/A'}°',
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
