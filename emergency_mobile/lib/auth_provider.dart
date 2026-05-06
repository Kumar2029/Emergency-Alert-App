import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  String? _userName;

  String? get token => _token;
  String? get userName => _userName;
  bool get isAuthenticated => _token != null;

  AuthProvider() {
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    _userName = prefs.getString('user_name');
    notifyListeners();
  }

  Future<void> setAuth(String token, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_name', name);
    _token = token;
    _userName = name;
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_name');
    _token = null;
    _userName = null;
    notifyListeners();
  }
}
