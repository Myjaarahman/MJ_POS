import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  // Sign In (Same as before)
  Future<void> signIn(String email, String password) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  // Sign Out (Same as before)
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // --- NEW: SaaS Registration Flow ---
  Future<void> signUpOwner({
    required String email, 
    required String password, 
    required String businessName
  }) async {
    // 1. Create the User Account (Auth)
    final AuthResponse res = await _supabase.auth.signUp(
      email: email, 
      password: password
    );

    final user = res.user;
    if (user == null) throw "Registration failed";

    // 2. Create the Business in the Database
    // We use .select() to get the ID of the new business back
    final businessData = await _supabase.from('businesses').insert({
      'name': businessName,
      'owner_id': user.id,
    }).select().single();

    final newBusinessId = businessData['id'];

    // 3. Link the User Profile to this Business
    // (The trigger already created the profile row, we just update it)
    await _supabase.from('profiles').update({
      'business_id': newBusinessId,
      'role': 'owner', // The first person is the Owner
    }).eq('id', user.id);
  }
}