import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/crypto_service.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'dart:typed_data';
import 'chat_screen.dart';
import 'search_screen.dart';
import 'auth_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List<dynamic> _chats = [];
  bool _loading = true;
  String? _nickname;
  int? _myUserId;
  StreamSubscription? _chatSubscription; // ← НОВОЕ

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _myUserId = prefs.getInt('userId');
    await _loadNickname();
    await _loadChats();
    _listenToMessages();
  }

  Future<void> _loadNickname() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _nickname = prefs.getString('nickname'));
  }

  Future<void> _loadChats() async {
    try {
      final chats = await ApiService().getChats();
      setState(() {
        _chats = chats;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _listenToMessages() {
    // ← ИЗМЕНЕНО: подписка на chatUpdateStream вместо messageStream
    _chatSubscription = SocketService().chatUpdateStream.listen((event) {
      final type = event['type'];
      
      if (type == 'new_message') {
        // Перезагружаем список чатов при новом сообщении
        _loadChats();
      } else if (type == 'message_deleted') {
        // Опционально: обновляем при удалении сообщений
        _loadChats();
      }
    });
  }

  @override
  void dispose() {
    _chatSubscription?.cancel(); // ← НОВОЕ
    super.dispose();
  }
  

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    SocketService().disconnect();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen(savedNickname: null)),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.parse(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _decryptLastMessage(String? lastMessage) {
    if (lastMessage == null || lastMessage.isEmpty) return 'No messages yet';
    
    try {
      final messageData = jsonDecode(lastMessage);
      
      // Если это уже расшифрованное сообщение (текст)
      if (messageData is String) {
        return messageData;
      }
      
      // Если это зашифрованное сообщение
      if (messageData is Map) {
        final content = messageData['content'];
        final encryptedKeys = messageData['encrypted_keys'];
        
        if (content == null || encryptedKeys == null) {
          return 'No messages yet';
        }
        
        final contentJson = jsonDecode(content);
        final keysMap = encryptedKeys is Map
            ? Map<String, dynamic>.from(encryptedKeys)
            : jsonDecode(encryptedKeys);
        
        final myKey = keysMap[_myUserId.toString()];
        
        if (myKey == null) {
          return '[Encrypted]';
        }
        
        try {
          final decryptedAESKey = CryptoService().decryptAESKey(myKey.toString());
          final decrypted = _decryptWithAES(
            contentJson['data'],
            decryptedAESKey,
            contentJson['iv'],
          );
          return decrypted;
        } catch (e) {
          return '[Encrypted]';
        }
      }
      
      return 'No messages yet';
    } catch (e) {
      // Если это просто текст, вернуть как есть
      return lastMessage;
    }
  }

  String _decryptWithAES(String encryptedData, Uint8List aesKey, String ivBase64) {
    try {
      final key = enc.Key(aesKey);
      final iv = enc.IV.fromBase64(ivBase64);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(encryptedData, iv: iv);
    } catch (e) {
      return '[Encrypted]';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1c1c1c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202020),
        title: Text(
          _nickname ?? 'Chats',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _chats.isEmpty
          ? const Center(child: Text('Актуальных переписок нет'))
          : ListView.builder(
              itemCount: _chats.length,
              itemBuilder: (context, index) {
                final chat = _chats[index];
                final lastMessage = _decryptLastMessage(chat['last_message']);
                
                return ListTile(
                  title: Text(
                    chat['partner_nickname'] ?? 'Unknown',
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _formatTime(chat['last_message_time']),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: chat['id'],
                          partnerId: chat['partner_id'],
                          partnerNickname: chat['partner_nickname'],
                        ),
                      ),
                    ).then((_) => _loadChats());
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.search),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchScreen()),
          ).then((_) => _loadChats());
        },
      ),
    );
  }
}