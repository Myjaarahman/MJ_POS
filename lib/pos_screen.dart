import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async'; // Needed for the stream subscription
import 'payment_screen.dart'; 
import 'add_product_screen.dart';
import 'receipts_screen.dart';
import 'kitchen_screen.dart'; 

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Data Variables
  List<Map<String, dynamic>> _cart = [];
  int? _selectedWaitingNumber;
  
  // Real-Time Busy Numbers
  List<int> _unavailableNumbers = []; 
  StreamSubscription? _orderSubscription; // To manage the listener

  final TextEditingController _waitingNumberController = TextEditingController();
  
  // Business Info
  String _businessName = "Loading...";
  String _role = "Cashier"; 

  // --- WHITE THEME COLORS ---
  final Color _bg = Colors.white;
  final Color _greenBtn = const Color(0xFF4CAF50);
  final Color _lightGrey = const Color(0xFFF5F5F5);

  @override
  void initState() {
    super.initState();
    _subscribeToOrders(); // Start listening immediately
    _fetchBusinessInfo(); 
  }

  @override
  void dispose() {
    _orderSubscription?.cancel(); // Stop listening when screen closes
    super.dispose();
  }

  Future<void> _fetchBusinessInfo() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final profile = await supabase.from('profiles').select('business_id, role').eq('id', user.id).single();
      final businessId = profile['business_id'];
      
      setState(() {
        _role = profile['role'].toString().toUpperCase();
      });

      if (businessId != null) {
        final business = await supabase.from('businesses').select('name').eq('id', businessId).single();
        if (mounted) setState(() => _businessName = business['name']);
      }
    } catch (e) {
      debugPrint("Error fetching business info: $e");
    }
  }

  // --- THE REAL-TIME LISTENER ---
  void _subscribeToOrders() {
    // This stream listens to the 'orders' table 24/7
    _orderSubscription = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .listen((data) {
          if (mounted) {
            setState(() {
              // Filter: Only show numbers for 'pending' or 'cooking' orders.
              // 'completed' orders will be automatically removed from this list.
              _unavailableNumbers = data
                  .where((order) => order['status'] == 'pending' || order['status'] == 'cooking')
                  .map((order) => order['waiting_number'] as int)
                  .toList()
                  ..sort(); 
            });
          }
        });
  }

  void _addToCart(Map<String, dynamic> product) {
    setState(() {
      final index = _cart.indexWhere((item) => item['id'] == product['id']);
      if (index != -1) {
        _cart[index]['qty']++;
      } else {
        _cart.add({
          'id': product['id'],
          'name': product['name'],
          'price': product['price'],
          'qty': 1,
          'notes': '',
        });
      }
    });
  }

  // Edit Cart Dialog
  void _editCartItem(int index) {
    final item = _cart[index];
    final noteCtrl = TextEditingController(text: item['notes']);
    int tempQty = item['qty'];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text("Edit ${item['name']}"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                        onPressed: () {
                          if (tempQty > 1) setDialogState(() => tempQty--);
                        },
                      ),
                      Text(tempQty.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: Icon(Icons.add_circle, color: _greenBtn),
                        onPressed: () => setDialogState(() => tempQty++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: "Special Instruction",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() => _cart.removeAt(index)); 
                    Navigator.pop(context);
                  },
                  child: const Text("Remove", style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _greenBtn),
                  onPressed: () {
                    setState(() {
                      _cart[index]['qty'] = tempQty;
                      _cart[index]['notes'] = noteCtrl.text;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("Save", style: TextStyle(color: Colors.white)),
                )
              ],
            );
          },
        );
      },
    );
  }

  double get _totalAmount => _cart.fold(0, (sum, item) => sum + (item['price'] * item['qty']));

  void _autoPickNumber() {
    for (int i = 1; i <= 50; i++) {
      if (!_unavailableNumbers.contains(i)) {
        setState(() {
          _selectedWaitingNumber = i;
          _waitingNumberController.text = i.toString();
        });
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All numbers 1-50 are full!")));
  }

  void _goToPayment() async {
    if (_cart.isEmpty) return;
    if (_selectedWaitingNumber == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Select Waiting Number!"), backgroundColor: Colors.orange));
      return;
    }

    if (_unavailableNumbers.contains(_selectedWaitingNumber)) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That number is already taken!"), backgroundColor: Colors.red));
       return;
    }

    final bool? paymentSuccess = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => PaymentScreen(cart: _cart, totalAmount: _totalAmount, waitingNumber: _selectedWaitingNumber!))
    );

    if (paymentSuccess == true) {
      setState(() {
        _cart.clear();
        _selectedWaitingNumber = null;
        _waitingNumberController.clear();
      });
      // The listener will automatically handle updating the busy numbers
    }
  }

  // --- DRAWER ---
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.white),
            accountName: Text(_businessName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
            accountEmail: Text("POS 1 • $_role", style: const TextStyle(color: Colors.grey)),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.store, color: Colors.white)),
          ),
          _buildDrawerItem(Icons.point_of_sale, "Sales", onTap: () => Navigator.pop(context)),
          _buildDrawerItem(Icons.receipt_long, "Receipts", onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptsScreen()));
          }),
          _buildDrawerItem(Icons.kitchen, "Kitchen Station", onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const KitchenScreen()));
          }),
          const Divider(),
          _buildDrawerItem(Icons.bar_chart, "Back office", onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen()));
          }),
          const Divider(),
          _buildDrawerItem(Icons.logout, "Logout", onTap: () async {
            await supabase.auth.signOut();
            if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
          }),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, {VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[700]),
      title: Text(title, style: const TextStyle(color: Colors.black)),
      onTap: onTap ?? () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bg,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.black),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Row(
          children: [
            const Text("All items", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            const Icon(Icons.arrow_drop_down, color: Colors.black),
            const Spacer(),
          ],
        ),
      ),
      body: Row(
        children: [
          // --- LEFT: PRODUCT GRID ---
          Expanded(
            flex: 6,
            child: Container(
              color: _lightGrey,
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: supabase.from('products').stream(primaryKey: ['id']),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final products = snapshot.data!;
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180, childAspectRatio: 1.0, crossAxisSpacing: 10, mainAxisSpacing: 10,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return GestureDetector(
                        onTap: () => _addToCart(product),
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]),
                          child: Stack(
                            children: [
                              Center(child: Text(product['name'], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                              Positioned(bottom: 8, right: 8, child: Text("RM ${product['price']}", style: const TextStyle(color: Colors.grey, fontSize: 12))),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // --- RIGHT: CART & WAITING NUMBERS ---
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300))),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _waitingNumberController,
                                decoration: const InputDecoration(labelText: "Waiting No.", border: OutlineInputBorder(), isDense: true),
                                keyboardType: TextInputType.number,
                                onChanged: (val) => setState(() => _selectedWaitingNumber = int.tryParse(val)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(onPressed: _autoPickNumber, child: const Text("Auto Pick"))
                          ],
                        ),
                        
                        // --- HERE IS THE MISSING BUSY INDICATOR ---
                        if (_unavailableNumbers.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text("Busy Numbers (Kitchen Active):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            _unavailableNumbers.join(', '),
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ]
                        // ------------------------------------------
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _cart.isEmpty 
                    ? const Center(child: Text("No items selected", style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                      itemCount: _cart.length,
                      separatorBuilder: (_,__) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _cart[index];
                        return ListTile(
                          onTap: () => _editCartItem(index), 
                          title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: item['notes'] != '' ? Text(item['notes'], style: const TextStyle(color: Colors.blue, fontSize: 12)) : null,
                          trailing: Text("RM ${(item['price'] * item['qty']).toStringAsFixed(2)}"),
                          leading: CircleAvatar(backgroundColor: Colors.grey[200], child: Text("${item['qty']}", style: const TextStyle(color: Colors.black))),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Total", style: TextStyle(fontSize: 16)),
                            Text("RM ${_totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _goToPayment,
                            style: ElevatedButton.styleFrom(backgroundColor: _greenBtn),
                            child: const Text("CHARGE", style: TextStyle(color: Colors.white, fontSize: 18)),
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}