import 'package:flutter/material';
import '../data/api_client.dart';
import '../data/local_db.dart';
import '../data/socket_client.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ProfileScreen({super.key, required this.onLogout});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _bio = "";
  String _pfpUrl = "";
  String _activeNote = "";
  bool _isLoading = false;

  final _bioController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final myId = ApiClient.instance.userId;
    if (myId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final profile = await ApiClient.instance.getProfile(myId);
      setState(() {
        _bio = profile['bio'] ?? "";
        _pfpUrl = profile['profile_picture_url'] ?? "";
        _activeNote = profile['active_note'] ?? "";
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading profile: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateProfile() async {
    final newBio = _bioController.text.trim();
    
    try {
      await ApiClient.instance.updateProfile(newBio, _pfpUrl);
      Navigator.pop(context);
      _loadProfile();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profil mis à jour ! ✅"), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : $e")),
      );
    }
  }

  Future<void> _publishNote() async {
    final content = _noteController.text.trim();
    if (content.isEmpty) return;

    try {
      await ApiClient.instance.publishNote(content);
      Navigator.pop(context);
      _loadProfile();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Note publiée ! 🚀"), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : $e")),
      );
    }
  }

  void _showEditProfileDialog() {
    _bioController.text = _bio;
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
              const Text(
                "Modifier le profil",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bioController,
                maxLength: 150,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Décrivez-vous...",
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _updateProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Enregistrer", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showNoteDialog() {
    _noteController.text = _activeNote;
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
              const Text(
                "Mettre à jour ma note",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _noteController,
                maxLength: 60,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Partagez une note rapide...",
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _publishNote,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: Colors.white,
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

  Future<void> _logout() async {
    try {
      SocketClient.instance.disconnect();
      await ApiClient.instance.logout();
      await LocalDatabaseHelper.instance.clearDatabase();
      widget.onLogout();
    } catch (e) {
      print("Logout error: $e");
      widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryBg = Color(0xFF0A0E17);
    const cardBg = Color(0xFF111927);
    final username = ApiClient.instance.username ?? "Utilisateur";
    final myPublicKey = ApiClient.instance.publicKeyHex ?? "Inconnu";

    return Scaffold(
      backgroundColor: primaryBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Profil",
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: const Color(0xFF00E5FF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  // Large profile avatar
                  Center(
                    child: CircleAvatar(
                      radius: 54,
                      backgroundColor: const Color(0xFF00E5FF).withOpacity(0.10),
                      child: Text(
                        (username.length >= 2 ? username.substring(0, 2) : username).toUpperCase(),
                        style: const TextStyle(color: const Color(0xFF00E5FF), fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Username
                  Text(
                    username,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  
                  // Bio
                  Text(
                    _bio.isEmpty ? "Pas encore de biographie..." : _bio,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  
                  // Edit Profile and Add Note actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _showEditProfileDialog,
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text("Modifier Bio"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cardBg,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _showNoteDialog,
                        icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
                        label: const Text("Ma note"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cardBg,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                  
                  if (_activeNote.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: cardBg.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline, color: const Color(0xFF00E5FF), size: 20),
                          const SizedBox(width: 10),
                          Text(
                            "Statut actif : \"$_activeNote\"",
                            style: const TextStyle(color: Colors.white70, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 32),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),
                  
                  // Security Info Card
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Informations de Sécurité",
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoTile(
                          Icons.perm_identity,
                          "Identifiant de session",
                          "User #${ApiClient.instance.userId}",
                        ),
                        _buildInfoTile(
                          Icons.vpn_key_rounded,
                          "Clé d'identité publique (X25519)",
                          myPublicKey,
                          isCode: true,
                        ),
                        _buildInfoTile(
                          Icons.shield_outlined,
                          "Statut du trousseau",
                          "Privé et chiffré dans KeyStore",
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value, {bool isCode = false}) {
    const cardBg = Color(0xFF1E1A38);
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(16.0),
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00E5FF), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                if (isCode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      value,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 10,
                        color: Colors.greenAccent,
                      ),
                    ),
                  )
                else
                  Text(
                    value,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
