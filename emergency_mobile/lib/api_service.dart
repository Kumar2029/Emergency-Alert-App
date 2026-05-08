import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Use 10.0.2.2 for Android Emulator, or your local IP for physical devices
  static const String baseUrl = 'https://spokesman-wind-cedar.ngrok-free.dev';

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

  static Future<http.Response> sendAlert(String token, String location, {String category = "General"}) async {
    return await http.post(
      Uri.parse('$baseUrl/send_alert'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'location': location,
        'category': category
      }),
    );
  }

  static Future<http.Response> updateLocation(String token, String location, {String battery = "", String category = ""}) async {
    Map<String, String> body = {
      'location': location,
    };
    if (battery.isNotEmpty) body['battery'] = battery;
    if (category.isNotEmpty) body['category'] = category;

    return await http.post(
      Uri.parse('$baseUrl/update_location'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
  }

  static Future<http.StreamedResponse> uploadEvidence(String token, String filePath) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload_evidence'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    return await request.send();
  }

  static Future<http.Response> deactivateSos(String token) async {
    return await http.post(
      Uri.parse('$baseUrl/deactivate_sos'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}
