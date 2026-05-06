import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 10.0.2.2 for Android Emulator, or your local IP for physical devices
  static const String baseUrl = 'http://127.0.0.1:5000';

  static Future<http.Response> register(String email, String password, String name) async {
    return await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password, 'full_name': name}),
    );
  }

  static Future<http.Response> login(String email, String password) async {
    return await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
  }

  static Future<http.Response> getProfile(String token) async {
    return await http.get(
      Uri.parse('$baseUrl/profile'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  static Future<http.Response> updateProfile(String token, Map<String, dynamic> data) async {
    return await http.post(
      Uri.parse('$baseUrl/profile'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(data),
    );
  }

  static Future<http.Response> sendAlert(String token, String location) async {
    return await http.post(
      Uri.parse('$baseUrl/send_alert'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'location': location}),
    );
  }
}
