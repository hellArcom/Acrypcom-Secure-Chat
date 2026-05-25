import 'package:flutter/material';
import '../data/api_client.dart';
import '../data/local_db.dart';
import '../data/socket_client.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> _threads = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadThreads();
    // Refresh threads if a new message is received or socket state changes
    SocketClient.instance.addMessageListener(_onNewMessage);
    SocketClient.instance.addConnectionListener(_onSocketChanged);
  }

  @override
  void dispose() {
    SocketClient.instance.removeMessageListener(_onNewMessage);
    SocketClient.instance.removeConnectionListener(_onSocketChanged);
    super.dispose();
  }

  void _onNewMessage(int senderId, String text) {
    _loadThreads();
  }

  void _onSocketChanged() {
    if (mounted) {
      _loadThreads();
    }
  }

  Future<void> _loadThreads() async {
    final myId = ApiClient.instance.userId;
    if (myId == null) return;

    if (mounted && _threads.isEmpty) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // 1. Get active threads from local SQLite DB
      final threads = await LocalDatabaseHelper.instance.getActiveChats(myId);
      
      // 2. Fetch missing usernames / profile metadata from server for each thread
      final enrichedThreads = <Map<String, dynamic>>[];
      for (var thread in threads) {
        final counterPartyId = thread['counter_party_id'] as int;
        try {
          final profile = await ApiClient.instance.getProfile(counterPartyId);
          enrichedThreads.add({
            ...thread,
            'username': profile['username'],
            'public_key': profile['public_key'],
          });
        } catch (e) {
          // Fallback if network fails
          enrichedThreads.add({
            ...thread,
            'username': "User #$counterPartyId",
            'public_key': "",
          });
        }
      }

      if (mounted) {
        setState(() {
          _threads = enrichedThreads;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading chat threads: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startNewChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1A38),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (context) {
        return const StartChatSheet();
      },
    ).then((_) {
      // Reload threads after closing search sheet
      _loadThreads();
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryBg = Color(0xFF0A0E17);
    const cardBg = Color(0xFF111927);

    return Scaffold(
      backgroundColor: primaryBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Direct Messages",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadThreads,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: const Color(0xFF00E5FF)))
          : _threads.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.white24),
                      const SizedBox(height: 16),
                      const Text(
                        "Aucune discussion",
                        style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Démarrer une conversation chiffrée avec un ami.",
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _startNewChat,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("Rechercher un utilisateur"),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _threads.length,
                  itemBuilder: (context, index) {
                    final thread = _threads[index];
                    final counterPartyId = thread['counter_party_id'] as int;
                    final username = thread['username'] as String;
                    final publicKeyHex = thread['public_key'] as String;
                    final lastMessage = thread['last_message_text'] as String;
                    final lastTime = thread['last_message_time'] as String;
                    final unreadCount = thread['unread_count'] as int;

                    // Formatter details
                    final time = DateTime.tryParse(lastTime)?.toLocal() ?? DateTime.now();
                    final formattedTime = "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

                    return ListTile(
                      onTap: () {
                        // Open Chat Room Screen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatRoomScreen(
                              counterPartyId: counterPartyId,
                              counterPartyUsername: username,
                              counterPartyPublicKeyHex: publicKeyHex,
                            ),
                          ),
                        ).then((_) {
                          // Refresh unread counts upon returning
                          _loadThreads();
                        });
                      },
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFF00E5FF).withOpacity(0.10),
                        child: Text(
                          (username.length >= 2 ? username.substring(0, 2) : username).toUpperCase(),
                          style: const TextStyle(color: const Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        username,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: Text(
                        lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: unreadCount > 0 ? Colors.white : Colors.white38,
                          fontSize: 13,
                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formattedTime,
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          const SizedBox(height: 6),
                          if (unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: const BoxDecoration(
                                color: const Color(0xFF00E5FF),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                unreadCount.toString(),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: Colors.white,
        child: const Icon(Icons.message),
      ),
    );
  }
}

class StartChatSheet extends StatefulWidget {
  const StartChatSheet({super.key});

  @override
  State<StartChatSheet> createState() => _StartChatSheetState();
}

class _StartChatSheetState extends State<StartChatSheet> {
  final _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  String _searchError = "";

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = "";
    });

    try {
      final results = await ApiClient.instance.searchUsers(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _searchError = e.toString().replaceFirst("Exception: ", "");
        _isSearching = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Nouveau Chat E2EE",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white60),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search Input
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Rechercher un pseudonyme...",
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white60),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, color: const Color(0xFF00E5FF)),
                onPressed: _performSearch,
              ),
              filled: true,
              fillColor: Colors.black.withOpacity(0.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _performSearch(),
          ),
          const SizedBox(height: 16),
          // Results
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: const Color(0xFF00E5FF)))
                : _searchError.isNotEmpty
                    ? Center(child: Text(_searchError, style: const TextStyle(color: Colors.redAccent)))
                    : _searchResults.isEmpty
                        ? const Center(
                            child: Text(
                              "Entrez un pseudonyme existant pour débuter un chat chiffré.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white38, fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final user = _searchResults[index];
                              final username = user['username'] as String;
                              final userId = user['id'] as int;
                              final publicKeyHex = user['public_key'] as String;

                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFF00E5FF).withOpacity(0.10),
                                  child: Text(
                                    (username.length >= 2 ? username.substring(0, 2) : username).toUpperCase(),
                                    style: const TextStyle(color: const Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                subtitle: const Text("Chiffrement activé 🔒", style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white38),
                                onTap: () {
                                  try {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatRoomScreen(
                                          counterPartyId: userId,
                                          counterPartyUsername: username,
                                          counterPartyPublicKeyHex: publicKeyHex,
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    print("Nav error: $e");
                                  }
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
