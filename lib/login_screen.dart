import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  
  // Text Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _businessNameController = TextEditingController(); // New Field
  
  bool _isLoading = false;
  bool _isRegistering = false; 

  Future<void> _authenticate() async {
    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final businessName = _businessNameController.text.trim();

    try {
      if (_isRegistering) {
        // --- REGISTER NEW CAFE ---
        if (businessName.isEmpty) {
          throw "Please enter your Cafe/Business Name";
        }
        await _authService.signUpOwner(
          email: email, 
          password: password, 
          businessName: businessName
        );
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Business Created! Logging you in...")),
          );
          // Auto-login is usually handled by Supabase, but we can double check
        }
      } else {
        // --- NORMAL LOGIN ---
        await _authService.signIn(email, password);
      }
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.storefront, size: 80, color: Colors.indigo),
                const SizedBox(height: 20),
                Text(
                  _isRegistering ? "Register New Cafe" : "MJ POS Login",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
            
                // --- NEW: Business Name Field (Only shows during Register) ---
                if (_isRegistering)
                  Column(
                    children: [
                      TextField(
                        controller: _businessNameController,
                        decoration: const InputDecoration(
                          labelText: "Business Name (e.g. Mirza's Cafe)",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.business),
                        ),
                      ),
                      const SizedBox(height: 15),
                    ],
                  ),
                // -------------------------------------------------------------
            
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: "Email",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: "Password",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 25),
                
                _isLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _authenticate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(_isRegistering ? "Create Business" : "Login"),
                        ),
                      ),
                
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isRegistering = !_isRegistering;
                    });
                  },
                  child: Text(
                    _isRegistering
                        ? "Already have an account? Login"
                        : "Start a new Business? Register",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}