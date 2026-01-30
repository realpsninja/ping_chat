import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final String baseUrl = 'https://plugins.timeto.watch';
  String? _token;

  void setToken(String token) => _token = token;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<Map<String, dynamic>> register(String pin) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/register'),
      headers: _headers,
      body: jsonEncode({'pin': pin}),
    );
    if (res.statusCode != 201) throw Exception('Registration failed');
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> login(String nickname, String pin) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: _headers,
      body: jsonEncode({'nickname': nickname, 'pin': pin}),
    );
    if (res.statusCode != 200) throw Exception('Login failed');
    return jsonDecode(res.body);
  }

  Future<void> savePublicKey(String publicKey) async {
    await http.post(
      Uri.parse('$baseUrl/api/users/public-key'),
      headers: _headers,
      body: jsonEncode({'publicKey': publicKey}),
    );
  }

  Future<String?> getPublicKey(int userId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/users/$userId/public-key'),
      headers: _headers,
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body)['publicKey'];
    }
    return null;
  }
  
  Future<Map<String, dynamic>?> getUserPresence(int userId) async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/users/$userId/presence'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return null;
    } catch (e) {
      print('Failed to get user presence: $e');
      return null;
    }
  }

  Future<List<dynamic>> searchUsers(String query) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/users/search?q=$query'),
      headers: _headers,
    );
    if (res.statusCode != 200) return [];
    return jsonDecode(res.body)['users'];
  }

  Future<Map<String, dynamic>> startChat(int targetUserId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/chats/start'),
      headers: _headers,
      body: jsonEncode({'targetUserId': targetUserId}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Failed to start chat');
    }
    return jsonDecode(res.body)['chat'];
  }

  Future<List<dynamic>> getChats() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/chats'),
      headers: _headers,
    );
    if (res.statusCode != 200) return [];
    return jsonDecode(res.body)['chats'];
  }

  Future<List<dynamic>> getMessages(int chatId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/chats/$chatId/messages?limit=100'),
      headers: _headers,
    );
    if (res.statusCode != 200) return [];
    return jsonDecode(res.body)['messages'];
  }

  Future<void> deleteMessage(int messageId) async {
    await http.delete(
      Uri.parse('$baseUrl/api/messages/$messageId'),
      headers: _headers,
    );
  }

  Future<void> deleteChat(int chatId) async {
    await http.delete(
      Uri.parse('$baseUrl/api/chats/$chatId'),
      headers: _headers,
    );
  }

  Future<void> clearChatMessages(int chatId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/chats/$chatId/clear'),
      headers: _headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to clear chat messages');
    }
  }
  
  Future<void> deleteAccount() async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/account'),
      headers: _headers,
    );
    
    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['error'] ?? 'Failed to delete account';
      throw Exception(error);
    }
  }
}