import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<dynamic> _results = [];
  bool _searching = false;

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 2) return;

    setState(() => _searching = true);

    try {
      final users = await ApiService().searchUsers(query);
      setState(() {
        _results = users;
        _searching = false;
      });
    } catch (e) {
      setState(() => _searching = false);
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
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1c1c1e),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202020),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Text(
                'Поиск контактов',
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search by nickname',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF33333e),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                suffixIcon: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3d3d50),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.search,
                      color: Color(0xFF8b8bd9),
                    ),
                    onPressed: _search,
                  ),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _search(),
            ),
          ),
          Expanded(
            child: _searching
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : _results.isEmpty
                ? const Center(
                    child: Text(
                      'No users found',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final user = _results[index];
                      return Container(
                        color: index.isEven 
                          ? const Color(0xFF1c1c1e) 
                          : const Color(0xFF202020),
                        child: ListTile(
                          title: Text(
                            user['nickname'],
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            'Last seen: ${_formatTime(user['last_seen'])}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          onTap: () => _startChat(user['id'], user['nickname']),
                          tileColor: const Color(0xFF282836),
                          hoverColor: const Color(0xFF282836),
                          focusColor: const Color(0xFF282836),
                          selectedTileColor: const Color(0xFF282836),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return 'Unknown';
    final dt = DateTime.parse(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);
    
    if (diff.inMinutes < 5) return 'Online';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}