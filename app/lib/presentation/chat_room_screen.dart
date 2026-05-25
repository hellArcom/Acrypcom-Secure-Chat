import 'dart:async';
import 'package:flutter/material';
import '../data/api_client.dart';
import '../data/local_db.dart';
import '../data/socket_client.dart';

class ChatRoomScreen extends StatefulWidget {
  final int counterPartyId;
  final String counterPartyUsername;
  final String counterPartyPublicKeyHex;

  const ChatRoomScreen({
    super.key,
    required this.counterPartyId,
    required this.counterPartyUsername,
    required this.counterPartyPublicKeyHex,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  String _latestPublicKeyHex = "";

  @override
  void initState() {
    super.initState();
    _latestPublicKeyHex = widget.counterPartyPublicKeyHex;
    _refreshPublicKey();
    _loadMessages();
    _markRead();
    SocketClient.instance.addMessageListener(_onNewMessageReceived);
  }

  Future<void> _refreshPublicKey() async {
    try {
      final profile = await ApiClient.instance.getProfile(widget.counterPartyId);
      final key = profile['public_key'] as String?;
      if (key != null && key.isNotEmpty) {
        _latestPublicKeyHex = key;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    SocketClient.instance.removeMessageListener(_onNewMessageReceived);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onNewMessageReceived(int senderId, String text) {
    if (senderId == widget.counterPartyId) {
      _loadMessages();
      _markRead();
    }
  }

  Future<void> _markRead() async {
    try {
      final myId = ApiClient.instance.userId;
      if (myId == null) return;
      await LocalDatabaseHelper.instance.markAsRead(myId, widget.counterPartyId);
    } catch (e) {
      print("markRead error: $e");
    }
  }

  Future<void> _loadMessages() async {
    final myId = ApiClient.instance.userId;
    if (myId == null) return;

    if (mounted && _messages.isEmpty) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final messages = await LocalDatabaseHelper.instance.getChatMessages(myId, widget.counterPartyId);
      
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(messages);
          _isLoading = false;
        });
        
        // Scroll to bottom
        Timer(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      print("Error loading messages: $e");
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      await _refreshPublicKey();

      final success = await SocketClient.instance.sendEncryptedMessage(
        recipientId: widget.counterPartyId,
        recipientPublicKeyHex: _latestPublicKeyHex,
        plaintext: text,
      );

      if (success) {
        _loadMessages();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Échec de l'envoi. Connexion perdue ?"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      print("Send error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : ${e.toString()}")),
        );
      }
    }
  }

  void _showCryptoDetails() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1A38),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_rounded, color: Colors.greenAccent, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    "Détails du chiffrement E2EE",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                "Toutes les transmissions privées avec cet utilisateur sont sécurisées par chiffrement à courbe elliptique X25519 et jeton d'authentification AES-GCM.",
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              const Text(
                "CLÉ SOCIALE PUBLIQUE DU CONTACT :",
                style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: SelectableText(
                  widget.counterPartyPublicKeyHex.isEmpty
                      ? "Indisponible en mode hors ligne"
                      : widget.counterPartyPublicKeyHex,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Le serveur local ne stocke pas et ne voit jamais vos clés d'authentification ou le texte clair des messages.",
                style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryBg = Color(0xFF0A0E17);
    const cardBg = Color(0xFF111927);
    final myId = ApiClient.instance.userId;

    return Scaffold(
      backgroundColor: primaryBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF00E5FF).withOpacity(0.10),
              child: Text(
                (widget.counterPartyUsername.length >= 2 ? widget.counterPartyUsername.substring(0, 2) : widget.counterPartyUsername).toUpperCase(),
                style: const TextStyle(color: const Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.counterPartyUsername,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Row(
                    children: [
                      Icon(Icons.lock, color: Colors.greenAccent, size: 10),
                      SizedBox(width: 4),
                      Text(
                        "Sécurisé (E2EE)",
                        style: TextStyle(color: Colors.greenAccent, fontSize: 10),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: _showCryptoDetails,
          ),
        ],
      ),
      body: Column(
        children: [
          // Chat bubbles
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: const Color(0xFF00E5FF)))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_outline, size: 48, color: Colors.white24),
                            const SizedBox(height: 12),
                            Text(
                              "Début de votre conversation chiffrée avec ${widget.counterPartyUsername}",
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final senderId = msg['sender_id'] as int;
                          final text = msg['message_text'] as String;
                          final isMe = senderId == myId;

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4.0),
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: isMe ? const Color(0xFF00E5FF) : cardBg,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16.0),
                                  topRight: const Radius.circular(16.0),
                                  bottomLeft: Radius.circular(isMe ? 16.0 : 0.0),
                                  bottomRight: Radius.circular(isMe ? 0.0 : 16.0),
                                ),
                              ),
                              child: Text(
                                text,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          
          // Input field
          Container(
            padding: const EdgeInsets.all(12.0),
            color: cardBg.withOpacity(0.5),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Écrire un message sécurisé...",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: const Color(0xFF00E5FF)),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
