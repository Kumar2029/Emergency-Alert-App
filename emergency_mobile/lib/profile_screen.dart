import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'api_service.dart';
import 'auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _medicalController = TextEditingController();
  List<Map<String, String>> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final auth = context.read<AuthProvider>();
    final res = await ApiService.getProfile(auth.token!);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        _nameController.text = data['full_name'] ?? '';
        _medicalController.text = data['medical_notes'] ?? '';
        _contacts = List<Map<String, String>>.from(
          data['contacts'].map((c) => Map<String, String>.from(c))
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    final auth = context.read<AuthProvider>();
    final res = await ApiService.updateProfile(auth.token!, {
      'full_name': _nameController.text,
      'medical_notes': _medicalController.text,
      'contacts': _contacts,
    });
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated!")));
    }
  }

  void _addContact() {
    showDialog(
      context: context,
      builder: (context) {
        final nameC = TextEditingController();
        final emailC = TextEditingController();
        return AlertDialog(
          title: const Text("Add Contact"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameC, decoration: const InputDecoration(labelText: "Name")),
              TextField(controller: emailC, decoration: const InputDecoration(labelText: "Email")),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                setState(() => _contacts.add({"name": nameC.text, "email": emailC.text}));
                Navigator.pop(context);
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text("Safety Profile"), actions: [
        IconButton(onPressed: _saveProfile, icon: const Icon(Icons.save))
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Personal Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Full Name", border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(
            controller: _medicalController, 
            maxLines: 3, 
            decoration: const InputDecoration(labelText: "Medical Notes (Allergies, Blood Type, etc.)", border: OutlineInputBorder())
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Emergency Contacts", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _addContact, icon: const Icon(Icons.add_circle, color: Colors.greenAccent)),
            ],
          ),
          ..._contacts.map((c) => ListTile(
            title: Text(c['name']!),
            subtitle: Text(c['email']!),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => setState(() => _contacts.remove(c)),
            ),
          )).toList(),
        ],
      ),
    );
  }
}
