import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api_service.dart';
import 'auth_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        final res = await ApiService.login(_emailController.text, _passwordController.text);
        final data = jsonDecode(res.body);
        if (res.statusCode == 200) {
          context.read<AuthProvider>().setAuth(data['token'], data['full_name']);
        } else {
          _showError(data['message']);
        }
      } else {
        final res = await ApiService.register(_emailController.text, _passwordController.text, _nameController.text);
        if (res.statusCode == 201) {
          setState(() => _isLogin = true);
          _showError("Registration successful! Please login.");
        } else {
          final data = jsonDecode(res.body);
          _showError(data['message']);
        }
      }
    } catch (e) {
      _showError("Connection error. Check your server.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.redAccent),
              const SizedBox(height: 20),
              Text(
                _isLogin ? "Welcome Back" : "Create Account",
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              if (!_isLogin)
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder()),
                ),
              if (!_isLogin) const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  child: _isLoading ? const CircularProgressIndicator() : Text(_isLogin ? "LOGIN" : "SIGN UP"),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? "Don't have an account? Sign Up" : "Already have an account? Login"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
