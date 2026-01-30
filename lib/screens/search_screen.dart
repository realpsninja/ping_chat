import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';
import '../widgets/custom_navigation_bar.dart';
import '../utils/status_utils.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<dynamic> _results = [];
  bool _searching = false;
  int _currentIndex = 1; // Индекс для поиска
  Timer? _searchTimer;
  String? _myNickname;
  int? _myUserId;

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
  }

  Future<void> _loadMyProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _myNickname = prefs.getString('nickname');
      _myUserId = prefs.getInt('userId');
    });
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _results.clear();
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);

    try {
      final users = await ApiService().searchUsers(query);
      setState(() {
        _results = users;
        _searching = false;
      });
    } catch (e) {
      setState(() => _searching = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка поиска: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onSearchChanged(String value) {
    // Отменяем предыдущий таймер
    _searchTimer?.cancel();
    
    if (value.trim().length >= 2) {
      // Запускаем новый таймер для задержки поиска
      _searchTimer = Timer(const Duration(milliseconds: 500), _search);
    } else {
      setState(() {
        _results.clear();
        _searching = false;
      });
    }
  }

  Future<void> _startChat(int userId, String nickname) async {
    try {
      final chat = await ApiService().startChat(userId);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chat['id'],
            partnerId: userId,
            partnerNickname: nickname,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка создания чата: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Обработка навигации
  void _onNavigationItemSelected(int index) {
    setState(() {
      _currentIndex = index;
    });

    switch (index) {
      case 0: // Чаты
        Navigator.pop(context);
        break;
      case 1: // Поиск (уже на этой странице)
        break;
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1c1c1c),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1c1c1c),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 22,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text(
              'Поиск друзей',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20, // Такой же размер как на chats_screen
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_myNickname != null && _myNickname!.isNotEmpty)
              Text(
                _myNickname!,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Поле поиска
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2a2a2a),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  const Icon(Icons.search, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Введите имя пользователя...',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      onChanged: _onSearchChanged,
                      autofocus: true,
                    ),
                  ),
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Подсказка
          if (_searchController.text.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                'Введите минимум 2 символа для поиска',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
            ),
          
          // Результаты поиска
          Expanded(
            child: _searching && _results.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : _results.isEmpty && _searchController.text.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.person_search,
                              color: Colors.grey,
                              size: 60,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Пользователи не найдены',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (context, index) {
                          final user = _results[index];
                          final isOnline = user['is_online'] ?? false;
                          final lastSeen = user['last_seen'] != null
                              ? DateTime.parse(user['last_seen'])
                              : null;
                          final statusText = StatusUtils.formatLastSeen(lastSeen, isOnline);
                          
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2a2a2a),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFF7474d6),
                                radius: 24,
                                child: Text(
                                  (user['nickname'] ?? '?')[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                user['nickname'] ?? 'Unknown',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: isOnline ? Colors.green : Colors.grey,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      statusText,
                                      style: TextStyle(
                                        color: isOnline ? Colors.green : Colors.grey[300],
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7474d6),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Написать',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              onTap: () => _startChat(user['id'], user['nickname']),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: CustomNavigationBar(
        currentIndex: _currentIndex,
        onItemSelected: _onNavigationItemSelected,
        showNavBar: true,
        nickname: _myNickname,
        userId: _myUserId,
      ),
    );
  }
}