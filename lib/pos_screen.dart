import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async'; 
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
  StreamSubscription? _orderSubscription; 

  // --- CATEGORY VARIABLES (NEW) ---
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId; // Null = "All Items"
  String _selectedCategoryName = "All items";

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
    _subscribeToOrders(); 
    _fetchBusinessInfo();
    _fetchCategories(); // <--- Load categories on startup
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    super.dispose();
  }

  // 1. Fetch Categories for the Dropdown
  Future<void> _fetchCategories() async {
    try {
      final response = await supabase.from('categories').select().order('name');
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint("Error fetching categories: $e");
    }
  }

  // 2. Helper to filter products
  Stream<List<Map<String, dynamic>>> _getProductsStream() {
    // If "All items" is selected, return everything
    if (_selectedCategoryId == null) {
      return supabase.from('products').stream(primaryKey: ['id']).order('name');
    } 
    // Otherwise, filter by category_id
    else {
      return supabase
          .from('products')
          .stream(primaryKey: ['id'])
          .eq('category_id', _selectedCategoryId!)
          .order('name');
    }
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

  void _subscribeToOrders() {
    _orderSubscription = supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .listen((data) {
          if (mounted) {
            setState(() {
              _unavailableNumbers = data
                  .where((order) => order['status'] == 'pending' || order['status'] == 'cooking' || order['status'] == 'ready')
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
                      labelText: "Special Instruction (e.g. No Sugar)",
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
                  child: const Text("Remove Item", style: TextStyle(color: Colors.red)),
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
                  child: const Text("Save Changes", style: TextStyle(color: Colors.white)),
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
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That number is already taken! Pick another."), backgroundColor: Colors.red));
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
    }
  }

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
        
        // --- 3. THE DROPDOWN BUTTON ---
        title: PopupMenuButton<int?>(
          // This creates the dropdown menu
          onSelected: (int? categoryId) {
            setState(() {
              _selectedCategoryId = categoryId;
              if (categoryId == null) {
                _selectedCategoryName = "All items";
              } else {
                final cat = _categories.firstWhere((e) => e['id'] == categoryId);
                _selectedCategoryName = cat['name'];
              }
            });
          },
          itemBuilder: (context) {
            List<PopupMenuEntry<int?>> list = [];
            // "All Items" Option
            list.add(const PopupMenuItem(value: null, child: Text("All items")));
            // Categories from DB
            for (var cat in _categories) {
              list.add(PopupMenuItem(value: cat['id'], child: Text(cat['name'])));
            }
            return list;
          },
          // The visual Button in the AppBar
          child: Row(
            children: [
              Text(_selectedCategoryName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              const Icon(Icons.arrow_drop_down, color: Colors.black),
            ],
          ),
        ),
        // ------------------------------

        actions: [
          const Spacer(),
        ],
      ),
      body: Row(
        children: [
          // --- LEFT: PRODUCT GRID ---
          Expanded(
            flex: 6,
            child: Container(
              color: _lightGrey,
              // --- 4. USE FILTERED STREAM ---
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _getProductsStream(), // Now uses the category filter
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final products = snapshot.data!;
                  
                  if (products.isEmpty) return const Center(child: Text("No items in this category"));

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
                        if (_unavailableNumbers.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            "Busy: ${_unavailableNumbers.join(', ')}",
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ]
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