import 'dart:ui';
import 'package:flutter/material';
import '../data/api_client.dart';
import '../crypto/e2ee.dart';
import '../data/socket_client.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController(text: "10.0.2.2:8000");
  
  bool _isLogin = true;
  bool _isLoading = false;
  bool _showServerConfig = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _serverController.text = ApiClient.instance.baseUrl.replaceAll("http://", "");
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final serverUrl = _serverController.text.trim();

    if (username.isEmpty || password.isEmpty || serverUrl.isEmpty) {
      setState(() {
        _errorMessage = "Veuillez remplir tous les champs.";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      // 1. Configure the server URL first
      ApiClient.instance.setBaseUrl(serverUrl);

      if (_isLogin) {
        final res = await ApiClient.instance.login(username, password);

        await ApiClient.instance.initSession();
        String? privateKeyHex = ApiClient.instance.privateKeyHex;
        String publicKeyHex = res['user']['public_key'] ?? "";

        if (privateKeyHex == null || ApiClient.instance.username != username) {
          final newKeyPair = await E2EEManager.generateKeyPair();
          privateKeyHex = await E2EEManager.getPrivateKeyHex(newKeyPair);
          publicKeyHex = await E2EEManager.getPublicKeyHex(newKeyPair);

          await ApiClient.instance.saveSession(
            token: res['token'],
            userId: res['user']['id'],
            username: res['user']['username'],
            publicKeyHex: publicKeyHex,
            privateKeyHex: privateKeyHex,
          );
          await ApiClient.instance.updateProfile("", "", publicKeyHex: publicKeyHex);
        } else {
          await ApiClient.instance.saveSession(
            token: res['token'],
            userId: res['user']['id'],
            username: res['user']['username'],
            publicKeyHex: publicKeyHex,
            privateKeyHex: privateKeyHex,
          );
        }
      } else {
        final keyPair = await E2EEManager.generateKeyPair();
        final privateKeyHex = await E2EEManager.getPrivateKeyHex(keyPair);
        final publicKeyHex = await E2EEManager.getPublicKeyHex(keyPair);

        final res = await ApiClient.instance.register(username, password, publicKeyHex);

        await ApiClient.instance.saveSession(
          token: res['token'],
          userId: res['user']['id'],
          username: res['user']['username'],
          publicKeyHex: publicKeyHex,
          privateKeyHex: privateKeyHex,
        );
      }

      await SocketClient.instance.connect();
      
      widget.onLoginSuccess();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF00E5FF);
    const backgroundColor = Color(0xFF0A0E17);
    const cardBgColor = Color(0xFF111927);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.purpleAccent.shade400.withOpacity(0.15),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28.0),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(32.0),
                    decoration: BoxDecoration(
                      color: cardBgColor.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(28.0),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              const Color(0xFF00E5FF),
                              const Color(0xFF4FC3F7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: const Icon(
                            Icons.terminal_rounded,
                            size: 56,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              const Color(0xFF00E5FF),
                              const Color(0xFF4FC3F7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: const Text(
                            "Acrypcom",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Chiffrement de bout en bout",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white38,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                         
                        TextField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "Nom d'utilisateur",
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(Icons.person_outline, color: Colors.white60),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.2),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: primaryColor, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "Mot de passe",
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(Icons.lock_outline, color: Colors.white60),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.2),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: primaryColor, width: 1.5),
                            ),
                          ),
                        ),
                        
                        
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _showServerConfig = !_showServerConfig;
                              });
                            },
                            icon: Icon(
                              _showServerConfig ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                              color: Colors.white60,
                              size: 18,
                            ),
                            label: const Text(
                              "Configuration Serveur Local",
                              style: TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ),
                        ),
                        if (_showServerConfig) ...[
                          TextField(
                            controller: _serverController,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: "IP:Port (ex: 192.168.1.15:8000)",
                              hintStyle: const TextStyle(color: Colors.white38),
                              prefixIcon: const Icon(Icons.dns_outlined, color: Colors.white60),
                              filled: true,
                              fillColor: Colors.black.withOpacity(0.2),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 24),
                        
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text(
                                    _isLogin ? "Se Connecter" : "Créer un Compte",
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isLogin = !_isLogin;
                              _errorMessage = "";
                            });
                          },
                          child: Text(
                            _isLogin
                                ? "Pas encore de compte ? S'inscrire"
                                : "Déjà inscrit ? Se connecter",
                            style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
