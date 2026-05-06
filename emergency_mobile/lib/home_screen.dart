import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
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
  String _status = "System Ready";

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startHolding() {
    setState(() {
      _isHolding = true;
      _progress = 0;
      _status = "HOLD TO ACTIVATE";
    });
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        _progress += 0.016; // Roughly 3 seconds to fill
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
      Position pos;
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        
        // Use real GPS with a longer timeout for the first fix
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e) {
        print("Real GPS Error: $e");
        setState(() => _status = "❌ GPS ERROR: $e");
        return; // Stop here so we don't send a fake location
      }
      
      final locationUrl = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";

      setState(() => _status = "📡 SENDING ALERT...");
      final auth = context.read<AuthProvider>();
      final res = await ApiService.sendAlert(auth.token!, locationUrl);

      if (res.statusCode == 200) {
        setState(() => _status = "✅ ALERT SENT");
      } else {
        setState(() => _status = "❌ ERROR SENDING");
      }
    } catch (e) {
      setState(() => _status = "❌ GPS ERROR");
    }
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Logged in as ${auth.userName}", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 50),
            GestureDetector(
              onLongPressStart: (_) => _startHolding(),
              onLongPressEnd: (_) => _stopHolding(),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Pulse Effect
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
                  // Progress Ring
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
                  // Main Button
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Colors.redAccent, Colors.red],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        "SOS",
                        style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text(
              _status,
              style: TextStyle(
                fontSize: 20, 
                fontWeight: FontWeight.bold, 
                color: _status.contains("✅") ? Colors.greenAccent : Colors.redAccent
              ),
            ),
            const SizedBox(height: 10),
            const Text("Hold button for 3 seconds", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
