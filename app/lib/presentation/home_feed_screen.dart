import 'package:flutter/material';
import '../data/api_client.dart';
import '../data/socket_client.dart';
import 'chat_list_screen.dart';

class HomeFeedScreen extends StatefulWidget {
  final VoidCallback onNavigateToProfile;
  final VoidCallback onNavigateToChats;
  const HomeFeedScreen({
    super.key,
    required this.onNavigateToProfile,
    required this.onNavigateToChats,
  });

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  List<dynamic> _notes = [];
  bool _isLoadingNotes = false;
  String _myActiveNote = "";
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotes();
    SocketClient.instance.addConnectionListener(_onSocketConnectionChanged);
  }

  @override
  void dispose() {
    SocketClient.instance.removeConnectionListener(_onSocketConnectionChanged);
    _noteController.dispose();
    super.dispose();
  }

  void _onSocketConnectionChanged() {
    if (mounted && SocketClient.instance.isConnected) {
      _loadNotes();
    }
  }

  Future<void> _loadNotes() async {
    if (mounted) {
      setState(() {
        _isLoadingNotes = true;
      });
    }

    try {
      final notes = await ApiClient.instance.getNotesFeed();
      final myProfile = await ApiClient.instance.getProfile(ApiClient.instance.userId!);

      if (mounted) {
        setState(() {
          _notes = notes;
          _myActiveNote = myProfile['active_note'] ?? "";
          _isLoadingNotes = false;
        });
      }
    } catch (e) {
      print("Error loading notes: $e");
      if (mounted) {
        setState(() {
          _isLoadingNotes = false;
        });
      }
    }
  }

  Future<void> _publishNote() async {
    final noteText = _noteController.text.trim();
    if (noteText.isEmpty) return;

    if (noteText.length > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Une note ne peut pas dépasser 60 caractères.")),
      );
      return;
    }

    try {
      await ApiClient.instance.publishNote(noteText);
      _noteController.clear();
      Navigator.pop(context);
      _loadNotes();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Statut partagé avec succès ! 🚀"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : ${e.toString()}")),
      );
    }
  }

  void _showPublishNoteDialog() {
    _noteController.text = _myActiveNote;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1A38),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      builder: (context) {
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
                    "Partager une pensée",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "Les notes sont visibles pendant 24 heures et s'affichent en haut de la messagerie.",
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Stack(
                alignment: Alignment.centerLeft,
                children: [
                  TextField(
                    controller: _noteController,
                    maxLength: 60,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Partagez une note de statut...",
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      counterStyle: const TextStyle(color: Colors.white38),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _publishNote,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: const Color(0xFF0A0E17),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Partager", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
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

    return Scaffold(
      backgroundColor: primaryBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              const Color(0xFF00E5FF),
              const Color(0xFF4FC3F7),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(bounds),
          child: const Text(
            "Acrypcom",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              color: Colors.white,
            ),
          ),
        ),
        actions: [
          
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SocketClient.instance.isConnected ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                SocketClient.instance.isConnected ? "En ligne" : "Reconnexion...",
                style: TextStyle(
                  color: SocketClient.instance.isConnected ? Colors.green : Colors.orange,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, color: Colors.white),
            onPressed: widget.onNavigateToChats,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotes,
        color: const Color(0xFF00E5FF),
        backgroundColor: cardBg,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              Padding(
                padding: const EdgeInsets.only(left: 16.0, top: 16.0, bottom: 8.0),
                child: Text(
                  "Notes de Statut",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              
              SizedBox(
                height: 125,
                child: _isLoadingNotes
                    ? const Center(child: CircularProgressIndicator(color: const Color(0xFF00E5FF)))
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        itemCount: _notes.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            
                            return GestureDetector(
                              onTap: _showPublishNoteDialog,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Column(
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      alignment: Alignment.center,
                                      children: [
                                        
                                        CircleAvatar(
                                          radius: 32,
                                          backgroundColor: Colors.grey.shade800,
                                          child: Text(
                                            _safeInitials(ApiClient.instance.username ?? "ME"),
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        
                                        Positioned(
                                          bottom: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: const Color(0xFF00E5FF),
                                            ),
                                            child: const Icon(Icons.add, size: 16, color: Colors.white),
                                          ),
                                        ),
                                        
                                        if (_myActiveNote.isNotEmpty)
                                          Positioned(
                                            top: -24,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              constraints: const BoxConstraints(maxWidth: 80),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(16),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withOpacity(0.2),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  )
                                                ],
                                              ),
                                              child: Text(
                                                _myActiveNote,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w500),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      "Votre note",
                                      style: TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          
                          final note = _notes[index - 1];
                          final username = note['username'] as String;
                          final content = note['content'] as String;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Column(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 32,
                                      backgroundColor: const Color(0xFF00E5FF).withOpacity(0.10),
                                      child: Text(
                                        _safeInitials(username),
                                        style: const TextStyle(color: const Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    
                                    Positioned(
                                      top: -24,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        constraints: const BoxConstraints(maxWidth: 80),
                                        decoration: BoxDecoration(
                                          color: cardBg,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: Colors.white12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.3),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ],
                                        ),
                                        child: Text(
                                          content,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.white, fontSize: 10),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  username,
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const Divider(color: Colors.white10, thickness: 1, height: 1),
              
              
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: cardBg.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(24.0),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    gradient: LinearGradient(
                      colors: [cardBg, cardBg.withOpacity(0.3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.terminal_rounded, color: Color(0xFF00E5FF), size: 24),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "Protocole de Sécurité",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Architecture zero-trust. Aucune information personnelle n'est requise.",
                          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 16),

                        
                        _buildSecurityItem(
                          Icons.vpn_key_outlined,
                          "Connexion initiale",
                          "ECC X25519 + Salt (PBKDF2)",
                        ),
                        _buildSecurityItem(
                          Icons.lock_outline,
                          "Chiffrement E2EE",
                          "AES-GCM 256 avec clé unique/message",
                        ),
                        _buildSecurityItem(
                          Icons.shuffle_rounded,
                          "Sécurité runtime",
                          "Clé renouvelée/min, anti-rejeu (UUID+ts), padding",
                        ),
                        _buildSecurityItem(
                          Icons.rotate_left_rounded,
                          "Rotation de clés",
                          "X25519 automatique toutes les 60s",
                        ),
                      ],
                  ),
                ),
              ),

              
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.photo_library_outlined, size: 48, color: Colors.white24),
                      const SizedBox(height: 12),
                      const Text(
                        "Bienvenue sur Acrypcom",
                        style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        "Allez dans l'onglet de discussion pour rechercher des contacts et démarrer une conversation chiffrée.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: widget.onNavigateToChats,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text("Démarrer un chat"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: const Color(0xFF0A0E17),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _safeInitials(String name) {
    if (name.length >= 2) return name.substring(0, 2).toUpperCase();
    return name.toUpperCase();
  }

  Widget _buildSecurityItem(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
