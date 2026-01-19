import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart'; 
import 'pos_screen.dart'; // Directs to Cashier Station (or swap for HomeScreen)

// Imports from your other files
import 'add_product_screen.dart'; 
import 'kitchen_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://edofoaaxpxwxkcbzvqsu.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVkb2ZvYWF4cHh3eGtjYnp2cXN1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg4MjE0NDgsImV4cCI6MjA4NDM5NzQ0OH0.PtS8a3yAJdIVOsz9vVRhCi7C7HmxjwzPGLdG_ovDzdU',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MJ POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        useMaterial3: true,
      ),
      // THE GATEKEEPER IS BACK (Fixed)
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          // 1. INSTANT CHECK: Do we already have a session?
          // This prevents the "Login every time" issue by checking memory first.
          final session = Supabase.instance.client.auth.currentSession;
          
          if (session != null) {
            return const HomeScreen(); // <--- GO STRAIGHT HOME
          }

          // 2. If no session, show Login
          return const LoginScreen();
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _cafeName = "Loading..."; 

  @override
  void initState() {
    super.initState();
    _getCafeName();
  }

  Future<void> _getCafeName() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profile = await supabase.from('profiles').select('business_id').eq('id', user.id).single();
      final businessId = profile['business_id'];

      final business = await supabase.from('businesses').select('name').eq('id', businessId).single();

      if (mounted) setState(() => _cafeName = business['name']);
    } catch (e) {
      if (mounted) setState(() => _cafeName = "Dashboard");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$_cafeName POS"), 
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              // The StreamBuilder in MyApp handles the redirect to Login automatically!
            },
          )
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Welcome to $_cafeName", 
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text("Select a mode for this device", style: TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 50),
              
              Wrap( 
                spacing: 20,
                runSpacing: 20,
                alignment: WrapAlignment.center,
                children: [
                  _buildMenuCard(
                    context,
                    title: "Cashier Station",
                    icon: Icons.point_of_sale,
                    color: Colors.blue,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen())),
                  ),
                  _buildMenuCard(
                    context,
                    title: "Kitchen Display",
                    icon: Icons.kitchen,
                    color: Colors.orange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KitchenScreen())),
                  ),
                  _buildMenuCard(
                    context,
                    title: "Back Office",
                    icon: Icons.inventory,
                    color: Colors.purple,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen())),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, {required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, size: 50, color: color),
              ),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}