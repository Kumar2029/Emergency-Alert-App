import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart' hide AndroidResource;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:torch_light/torch_light.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:camera/camera.dart';
import 'auth_provider.dart';
import 'api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  bool _isHolding = false;
  double _progress = 0;
  Timer? _timer;
  Timer? _trackingTimer;
  String _status = "System Ready";
  bool _isEmergencyInProgress = false; // New Robust Flag
  
  String _selectedCategory = "General";
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  final Battery _battery = Battery();
  String _correctPin = "1234"; // Default
  int _batteryLevel = 100;
  StreamSubscription? _batterySubscription;
  bool _isUpdatingCategory = false;
  bool _isBackgroundSosEnabled = false;
  static const platform = MethodChannel('com.emergency.app/hardware');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCorrectPin();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _checkAndRequestPermissions();
    _initBackgroundExecution();
    _initBatteryMonitoring();

    // Listen for hardware SOS (Triple press volume)
    platform.setMethodCallHandler((call) async {
      if (call.method == "triggerHardwareSOS") {
        _triggerEmergency();
      }
    });

    _checkAccessibilityService();
  }

  Future<void> _checkAccessibilityService() async {
    try {
      final bool isEnabled = await platform.invokeMethod('checkAccessibilityService');
      if (mounted) {
        setState(() {
          _isBackgroundSosEnabled = isEnabled;
        });
      }
    } catch (e) {
      debugPrint("Failed to check accessibility service: $e");
    }
  }

  void _initBatteryMonitoring() {
    _battery.batteryLevel.then((level) {
      if (mounted) setState(() => _batteryLevel = level);
    });
    _batterySubscription = _battery.onBatteryStateChanged.listen((_) async {
      final level = await _battery.batteryLevel;
      if (mounted) setState(() => _batteryLevel = level);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check permissions automatically when returning from settings
      _checkAndRequestPermissions();
      _checkAccessibilityService();
    }
  }

  Future<void> _fetchCorrectPin() async {
    try {
      final auth = context.read<AuthProvider>();
      if (auth.token != null) {
        final res = await ApiService.getProfile(auth.token!);
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (mounted) setState(() => _correctPin = data['rescue_pin'] ?? "1234");
        }
      }
    } catch (e) { /* PIN sync error handled silently */ }
  }

  Future<void> _checkAndRequestPermissions() async {
    // Check if SMS is denied by system (Restricted)
    if (await Permission.sms.isRestricted) {
      setState(() => _status = "⚠️ SMS BLOCKED BY SYSTEM");
      // Try to open settings for the user
      openAppSettings();
    }
    
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.sms,
      Permission.microphone,
      Permission.camera,
    ].request();

    if (statuses[Permission.sms]!.isPermanentlyDenied || statuses[Permission.sms]!.isDenied) {
      // If denied, take them to settings automatically
      await openAppSettings();
    }
  }

  Future<void> _initBackgroundExecution() async {
    const config = FlutterBackgroundAndroidConfig(
      notificationTitle: "Guardian Elite Protection",
      notificationText: "Background monitoring active for your safety",
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
    );
    bool hasPermissions = await FlutterBackground.initialize(androidConfig: config);
    if (hasPermissions) {
      await FlutterBackground.enableBackgroundExecution();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _timer?.cancel();
    _trackingTimer?.cancel();
    _batterySubscription?.cancel();
    _audioPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _startHolding() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isHolding = true;
      _progress = 0;
      _status = "HOLD TO ACTIVATE";
    });
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        _progress += 0.016; 
        if (_progress >= 1.0) {
          _progress = 1.0;
          _timer?.cancel();
          HapticFeedback.heavyImpact();
          _triggerEmergency();
        }
      });
    });
  }

  void _stopHolding() {
    _timer?.cancel();
    setState(() {
      _isHolding = false;
      _progress = 0;
      _status = "System Ready";
    });
  }

  Future<void> _triggerEmergency() async {
    if (_isEmergencyInProgress) return; // Prevent double triggers
    setState(() {
      _status = "🛰️ LOCATING...";
      _isEmergencyInProgress = true;
    });

    // Notify Server: SOS START
    final auth = context.read<AuthProvider>();
    if (auth.token != null) {
      ApiService.activateSos(auth.token!);
    }
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final locationUrl = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";
      final auth = context.read<AuthProvider>();
      
      // AUTO-ACTIVATE ALERTS
      setState(() => _status = "🚨 SOS ACTIVE: SMS");
      final profileRes = await ApiService.getProfile(auth.token!);
      final profileData = jsonDecode(profileRes.body);
      final contacts = profileData['contacts'] as List;

      for (var contact in contacts) {
          String phone = contact['phone']?.toString().replaceAll(RegExp(r'\D'), '') ?? "";
          if (phone.isNotEmpty) {
            // Hardened Format: If it's 10 digits, it's likely Indian (+91)
            String formattedPhone = phone;
            if (phone.length == 10) formattedPhone = "+91$phone";
            else if (!phone.startsWith('+')) formattedPhone = "+$phone";
            
            platform.invokeMethod('sendSms', {"phone": formattedPhone, "message": "SOS! Help me: $locationUrl"});
          }
      }

      // 2. ATTEMPT EMAIL & WHATSAPP
      setState(() => _status = "📧 SOS ACTIVE: ALERTS");
      await ApiService.sendAlert(auth.token!, locationUrl, category: _selectedCategory);

      // 3. START MEDIA PIPELINE & AUTOMATED CALL (NON-BLOCKING)
      setState(() => _status = "🎙️ SOS ACTIVE: RECORDING");
      _startTracking(auth.token!);
      
      // Fire and forget media & call handler to prevent blocking
      _handleMediaAndCall(auth.token!);
      
    } catch (e) {
      setState(() {
        _status = "❌ ERROR: $e";
        _isEmergencyInProgress = false;
      });
    }
  }

  void _showPinDialog() async {
    await _fetchCorrectPin(); // Sync latest PIN before showing dialog
    String inputPin = "";
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151515),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withOpacity(0.1))),
        title: const Text("RESCUE PIN REQUIRED", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your 4-digit security PIN to deactivate tracking.", style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),
            TextField(
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 10),
              decoration: InputDecoration(
                counterText: "",
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (val) => inputPin = val,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (inputPin == _correctPin) { // Use Custom PIN
                Navigator.pop(context);
                _stopSOS();
              } else {
                HapticFeedback.vibrate();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("INVALID PIN. TRACKING CONTINUES."), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
            child: const Text("VERIFY"),
          ),
        ],
      ),
    );
  }

  void _stopSOS() {
    debugPrint("🛑 DEACTIVATING SOS: SHUTTING DOWN ALL SYSTEMS");
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _recorder.stop();
    
    // Notify Server
    final auth = context.read<AuthProvider>();
    if (auth.token != null) {
      ApiService.deactivateSos(auth.token!);
    }

    setState(() {
      _isEmergencyInProgress = false;
      _status = "System Ready";
      _progress = 0;
    });
    HapticFeedback.lightImpact();
  }

  void _startTracking(String token) {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_isEmergencyInProgress) {
        timer.cancel();
        return;
      }
      try {
        Position currentPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        String currentUrl = "https://maps.google.com/?q=${currentPos.latitude},${currentPos.longitude}";
        
        int level = _batteryLevel;
        await ApiService.updateLocation(token, currentUrl, battery: level.toString());
      } catch (e) { /* Tracking error handled silently */ }
    });
  }

  Future<void> _handleMediaAndCall(String token) async {
    // 1. TRIGGER TWILIO VOICE CALL
    ApiService.triggerEmergencyCall(token).catchError((e) {
      debugPrint("Twilio Call Error: $e");
      return http.Response('', 500); // Silent fail
    });

    // 2. CAPTURE SNAPSHOT
    CameraController? cameraController;
    try {
      final cameras = await availableCameras();
      final frontCam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      
      // Initialize without audio to prevent mic lock conflict
      cameraController = CameraController(frontCam, ResolutionPreset.medium, enableAudio: false);
      await cameraController.initialize();
      
      final image = await cameraController.takePicture();
      ApiService.uploadSnapshot(token, image.path).catchError((_) => http.StreamedResponse(const Stream.empty(), 500));
      
      await cameraController.dispose();
      cameraController = null;
    } catch (e) {
      debugPrint("Snapshot Error: $e");
      cameraController?.dispose();
    }

    // 3. RECORD 15s AUDIO
    await _startRecordingEvidence(token);

    // 4. RECORD SHORT VIDEO
    try {
      final cameras = await availableCameras();
      final frontCam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      
      // Initialize with audio for the video evidence
      cameraController = CameraController(frontCam, ResolutionPreset.medium, enableAudio: true);
      await cameraController.initialize();
      
      await cameraController.startVideoRecording();
      await Future.delayed(const Duration(seconds: 7)); // Record 7 seconds
      
      final video = await cameraController.stopVideoRecording();
      ApiService.uploadVideo(token, video.path).catchError((_) => http.StreamedResponse(const Stream.empty(), 500));
      
      await cameraController.dispose();
    } catch (e) {
      debugPrint("Video Error: $e");
      cameraController?.dispose();
    }
  }

  Future<void> _startRecordingEvidence(String token) async {
    try {
      if (await _recorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/sos_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        
        // Wait 15 seconds asynchronously
        await Future.delayed(const Duration(seconds: 15));
        
        final filePath = await _recorder.stop();
        if (filePath != null) {
          setState(() => _status = "📤 UPLOADING...");
          final res = await ApiService.uploadEvidence(token, filePath);
          if (res.statusCode == 200) {
            setState(() => _status = "✅ SOS COMPLETE (SECURED)");
          } else {
            setState(() => _status = "⚠️ UPLOAD FAIL");
          }
        }
      }
    } catch (e) { 
      setState(() => _status = "⚠️ RECORD ERROR"); 
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final bool isEmergencyActive = _isEmergencyInProgress;

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 1.5,
                colors: [
                  Colors.red.withOpacity(0.05),
                  const Color(0xFF050505),
                ],
              ),
            ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("GUARDIAN", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 4)),
                            Text("ELITE", style: TextStyle(color: Colors.redAccent.shade400, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.logout, color: Colors.white, size: 24),
                              onPressed: () {
                                context.read<AuthProvider>().logout();
                                Navigator.pushReplacementNamed(context, '/login');
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.manage_accounts, color: Colors.white, size: 28),
                              onPressed: () => Navigator.pushNamed(context, '/profile'),
                            ),
                            const SizedBox(width: 8),
                            _statusBadge(),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    _telemetryGrid(),
                    const SizedBox(height: 20),
                    if (!_isBackgroundSosEnabled) ...[
                      _buildAccessibilityBanner(),
                      const SizedBox(height: 20),
                    ],
                    const Text("SELECT EMERGENCY TYPE", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    const SizedBox(height: 16),
                    _categorySelector(),
                    const SizedBox(height: 40),
                    _mainSOSButton(),
                    if (isEmergencyActive) ...[
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _showPinDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.withOpacity(0.1),
                          side: const BorderSide(color: Colors.greenAccent, width: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        ),
                        child: const Text("I AM SAFE / STOP TRACKING", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                    const SizedBox(height: 40),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  }

  Widget _buildAccessibilityBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text("Background SOS Disabled", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "Enable Background SOS monitoring to allow the hardware volume buttons to trigger an alert even when the app is closed or the screen is locked.",
            style: TextStyle(color: Colors.white70, fontSize: 10),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                try {
                  await platform.invokeMethod('openAccessibilitySettings');
                } catch (e) {
                  debugPrint("Failed to open settings: $e");
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("ENABLE NOW", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          )
        ],
      ),
    );
  }

  Widget _statusBadge() {
    bool isActive = _status.contains("ACTIVE");
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: isActive ? Colors.redAccent : Colors.greenAccent, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.redAccent : Colors.greenAccent,
              boxShadow: [BoxShadow(color: isActive ? Colors.red : Colors.green, blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isActive ? "SOS ACTIVE" : "SECURED",
            style: TextStyle(color: isActive ? Colors.redAccent : Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _telemetryGrid() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _telemetryItem(Icons.battery_charging_full, "BATTERY", "$_batteryLevel%"),
          _verticalDivider(),
          _telemetryItem(Icons.gps_fixed, "GPS", "LOCKED"),
          _verticalDivider(),
          _telemetryItem(Icons.security_update_good, "SIGNAL", "SECURE"),
        ],
      ),
    );
  }

  Widget _telemetryItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.5), size: 18),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 8, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, fontFamily: 'JetBrains Mono')),
      ],
    );
  }

  Widget _verticalDivider() {
    return Container(height: 30, width: 1, color: Colors.white.withOpacity(0.05));
  }

  Widget _categorySelector() {
    List<Map<String, dynamic>> categories = [
      {"name": "General", "icon": Icons.notification_important, "color": Colors.grey},
      {"name": "Security", "icon": Icons.security, "color": Colors.blue},
      {"name": "Medical", "icon": Icons.medical_services, "color": Colors.green},
      {"name": "Fire", "icon": Icons.local_fire_department, "color": Colors.orange},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: categories.map((cat) {
        bool isSelected = _selectedCategory == cat['name'];
        return GestureDetector(
          onTap: () {
            if (!_isUpdatingCategory) {
              setState(() {
                _selectedCategory = cat['name'];
                _isUpdatingCategory = true;
              });
              
              if (_status.contains("ACTIVE")) {
                final auth = context.read<AuthProvider>();
                Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low, timeLimit: const Duration(seconds: 5)).then((pos) {
                  final url = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";
                  ApiService.updateLocation(auth.token!, url, category: cat['name']).then((_) {
                    setState(() {
                      _status = "🛡️ ${cat['name'].toUpperCase()} SOS ACTIVE";
                      _isUpdatingCategory = false;
                    });
                  });
                }).catchError((_) => setState(() => _isUpdatingCategory = false));
              } else {
                setState(() => _isUpdatingCategory = false);
              }
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected ? cat['color'].withOpacity(0.2) : Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? cat['color'] : Colors.white.withOpacity(0.05), width: 1.5),
            ),
            child: Icon(cat['icon'], color: isSelected ? cat['color'] : Colors.white.withOpacity(0.3), size: 24),
          ),
        );
      }).toList(),
    );
  }

  Widget _mainSOSButton() {
    return GestureDetector(
      onLongPressStart: (_) => _startHolding(),
      onLongPressEnd: (_) => _stopHolding(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 260 + (_pulseController.value * 40),
                height: 260 + (_pulseController.value * 40),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.withOpacity(0.15 * (1 - _pulseController.value)), width: 2),
                ),
              );
            },
          ),
          SizedBox(
            width: 220,
            height: 220,
            child: CircularProgressIndicator(
              value: _progress,
              strokeWidth: 4,
              color: Colors.redAccent,
              backgroundColor: Colors.white.withOpacity(0.05),
            ),
          ),
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0A0A0A),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 2),
              boxShadow: [
                BoxShadow(color: Colors.red.withOpacity(0.2), blurRadius: 40, spreadRadius: 10),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("SOS", style: TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, letterSpacing: -2)),
                  Text(_isHolding ? "HOLDING..." : "PRESS & HOLD", style: TextStyle(color: Colors.redAccent.withOpacity(0.6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
