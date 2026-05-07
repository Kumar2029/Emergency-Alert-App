import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:torch_light/torch_light.dart';
import 'package:audioplayers/audioplayers.dart';
import 'auth_provider.dart';
import 'api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isHolding = false;
  double _progress = 0;
  Timer? _timer;
  Timer? _trackingTimer;
  String _status = "System Ready";
  
  bool _isSirenOn = false;
  bool _isStrobeOn = false;
  Timer? _strobeTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // New reliable siren source (direct mp3)
  final String sirenUrl = "https://www.soundjay.com/emergency/sounds/emergency-siren-01.mp3";
  
  final AudioRecorder _recorder = AudioRecorder();
  static const platform = MethodChannel('com.emergency.app/sms');

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _checkAndRequestPermissions();
  }

  Future<void> _checkAndRequestPermissions() async {
    // Check if SMS is denied by system (Restricted)
    if (await Permission.sms.isRestricted) {
      setState(() => _status = "⚠️ SMS BLOCKED BY SYSTEM");
      // Try to open settings for the user
      openAppSettings();
    }
    
    await [
      Permission.location,
      Permission.sms,
      Permission.microphone,
      Permission.camera,
    ].request();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    _trackingTimer?.cancel();
    _strobeTimer?.cancel();
    _audioPlayer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleSiren() async {
    try {
      if (_isSirenOn) {
        await _audioPlayer.stop();
      } else {
        // Set volume to max
        await _audioPlayer.setVolume(1.0);
        await _audioPlayer.play(UrlSource(sirenUrl));
      }
      setState(() => _isSirenOn = !_isSirenOn);
    } catch (e) {
      setState(() => _status = "⚠️ Siren Error: $e");
    }
  }

  Future<void> _toggleStrobe() async {
    try {
      if (_isStrobeOn) {
        _strobeTimer?.cancel();
        await TorchLight.disableTorch();
      } else {
        _strobeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          try {
            if (timer.tick % 2 == 0) {
              await TorchLight.enableTorch();
            } else {
              await TorchLight.disableTorch();
            }
          } catch (e) { timer.cancel(); }
        });
      }
      setState(() => _isStrobeOn = !_isStrobeOn);
    } catch (e) { print("Strobe error: $e"); }
  }

  void _startHolding() {
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
    setState(() => _status = "🛰️ LOCATING...");
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final locationUrl = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";
      final auth = context.read<AuthProvider>();
      
      // AUTO-ACTIVATE
      if (!_isStrobeOn) _toggleStrobe();
      if (!_isSirenOn) _toggleSiren();

      // 1. ATTEMPT SMS
      setState(() => _status = "🚨 SENDING SMS...");
      final profileRes = await ApiService.getProfile(auth.token!);
      final profileData = jsonDecode(profileRes.body);
      final contacts = profileData['contacts'] as List;

      for (var contact in contacts) {
        String phone = contact['phone']?.toString() ?? "";
        if (phone.isNotEmpty) {
          // Add a + if missing
          if (!phone.startsWith('+')) phone = "+91$phone"; // Replace 91 with your code
          platform.invokeMethod('sendSms', {"phone": phone, "message": "SOS! Help me: $locationUrl"});
        }
      }

      // 2. ATTEMPT EMAIL & WHATSAPP
      setState(() => _status = "📧 SERVER ALERTS...");
      await ApiService.sendAlert(auth.token!, locationUrl);

      // 3. START RECORDING
      setState(() => _status = "🎙️ RECORDING...");
      _startTracking(auth.token!);
      await _startRecordingEvidence(auth.token!);
      
    } catch (e) {
      setState(() => _status = "❌ ERROR: $e");
    }
  }

  void _startTracking(String token) {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      try {
        Position currentPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        String currentUrl = "https://maps.google.com/?q=${currentPos.latitude},${currentPos.longitude}";
        await ApiService.updateLocation(token, currentUrl);
      } catch (e) { print("Tracking error: $e"); }
    });
  }

  Future<void> _startRecordingEvidence(String token) async {
    try {
      if (await _recorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/sos_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        
        Timer(const Duration(seconds: 15), () async {
          final filePath = await _recorder.stop();
          if (filePath != null) {
            setState(() => _status = "📤 UPLOADING...");
            final res = await ApiService.uploadEvidence(token, filePath);
            if (res.statusCode == 200) {
              setState(() => _status = "✅ SOS COMPLETE");
            } else {
              setState(() => _status = "⚠️ UPLOAD FAIL");
            }
          }
        });
      }
    } catch (e) { setState(() => _status = "⚠️ RECORD ERROR"); }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Alert"),
        actions: [
          IconButton(onPressed: () => Navigator.pushNamed(context, '/profile'), icon: const Icon(Icons.person)),
          IconButton(onPressed: auth.logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Text("Logged in as ${auth.userName}", style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _deterrentButton(
                    icon: _isSirenOn ? Icons.volume_up : Icons.volume_off,
                    label: "Siren",
                    isActive: _isSirenOn,
                    color: Colors.blue,
                    onTap: _toggleSiren,
                  ),
                  const SizedBox(width: 20),
                  _deterrentButton(
                    icon: _isStrobeOn ? Icons.flash_on : Icons.flash_off,
                    label: "Strobe",
                    isActive: _isStrobeOn,
                    color: Colors.orange,
                    onTap: _toggleStrobe,
                  ),
                ],
              ),
              
              const SizedBox(height: 50),
              
              GestureDetector(
                onLongPressStart: (_) => _startHolding(),
                onLongPressEnd: (_) => _stopHolding(),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 220 + (_pulseController.value * 30),
                          height: 220 + (_pulseController.value * 30),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.redAccent.withOpacity(0.2 * (1 - _pulseController.value)),
                          ),
                        );
                      },
                    ),
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 10,
                        color: Colors.white,
                        backgroundColor: Colors.red.withOpacity(0.2),
                      ),
                    ),
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(colors: [Colors.redAccent, Colors.red]),
                        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)],
                      ),
                      child: const Center(child: Text("SOS", style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold, 
                  color: _status.contains("✅") ? Colors.greenAccent : Colors.redAccent
                ),
              ),
              const SizedBox(height: 10),
              const Text("Hold button for 3 seconds", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deterrentButton({required IconData icon, required String label, required bool isActive, required Color color, required VoidCallback onTap}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isActive ? color : color.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: isActive ? Colors.white : color, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
