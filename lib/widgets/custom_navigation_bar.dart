import 'dart:convert';
import 'package:flutter/material.dart';
import 'profile_bottom_sheet.dart';
import '../services/chat_actions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class CustomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onItemSelected;
  final bool showNavBar;
  final List<dynamic>? chats; // Для передачи в профиль
  final String? nickname; // Для отображения в профиле
  final int? userId; // Для профиля
  final VoidCallback? onReloadChats; // Для обновления чатов

  const CustomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onItemSelected,
    this.showNavBar = true,
    this.chats,
    this.nickname,
    this.userId,
    this.onReloadChats,
  });

  @override
  Widget build(BuildContext context) {
    if (!showNavBar) return const SizedBox.shrink();

    return Container(
      height: 70,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1c1c1c),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[800]!, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context: context,
            index: 0,
            icon: Icons.chat_bubble_outline,
            activeIcon: Icons.chat_bubble,
            label: 'Чаты',
          ),
          _buildNavItem(
            context: context,
            index: 1,
            icon: Icons.search_outlined,
            activeIcon: Icons.search,
            label: 'Поиск',
          ),
          _buildNavItem(
            context: context,
            index: 2,
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
            label: 'Настройки',
          ),
          _buildNavItem(
            context: context,
            index: 3,
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Профиль',
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = currentIndex == index;
    
    return GestureDetector(
      onTap: () => _handleItemTap(context, index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Иконка с анимацией
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isActive 
                  ? const Color(0xFF7474d6) 
                  : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isActive ? activeIcon : icon,
                color: isActive ? Colors.white : Colors.grey[400],
                size: 20,
              ),
            ),
            const SizedBox(height: 4),
            // Текст
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isActive ? Colors.white : Colors.grey[400],
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleItemTap(BuildContext context, int index) {
    switch (index) {
      case 0: // Чаты
        onItemSelected(index);
        break;
      case 1: // Поиск
        onItemSelected(index);
        break;
      case 2: // Настройки
        _showSettings(context);
        break;
      case 3: // Профиль
        _showProfile(context);
        break;
    }
  }

  void _showSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: const Text(
          'Настройки',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Раздел настроек находится в разработке',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfile(BuildContext context) {
    // Загружаем данные профиля если не переданы
    if (nickname == null || userId == null) {
      _loadAndShowProfile(context);
    } else {
      ProfileBottomSheet.show(
        context: context,
        nickname: nickname!,
        userId: userId!,
        chats: chats ?? [],
        onReloadChats: onReloadChats ?? () {},
      );
    }
  }

  Future<void> _loadAndShowProfile(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final nickname = prefs.getString('nickname') ?? 'Пользователь';
    final userId = prefs.getInt('userId') ?? 0;
    
    // Загружаем чаты если не переданы
    List<dynamic> loadedChats = chats ?? [];
    if (loadedChats.isEmpty) {
      try {
        final token = prefs.getString('token');
        if (token != null) {
          // Загружаем чаты через API
          final response = await http.get(
            Uri.parse('https://plugins.timeto.watch/api/chats'),
            headers: {
              'Authorization': 'Bearer $token',
            },
          );
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            loadedChats = data['chats'] ?? [];
          }
        }
      } catch (e) {
        print('Error loading chats for profile: $e');
      }
    }
    
    if (context.mounted) {
      ProfileBottomSheet.show(
        context: context,
        nickname: nickname,
        userId: userId,
        chats: loadedChats,
        onReloadChats: onReloadChats ?? () {},
      );
    }
  }

  // Публичный метод для показа диалога подтверждения (вынесен из ChatActionsService)
  static Future<bool> showConfirmationDialog(
    BuildContext context,
    String title,
    String content,
    String confirmText,
    Color confirmColor,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a2a),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(content, style: TextStyle(color: Colors.grey[300])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText, style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
    
    return confirmed ?? false;
  }
}