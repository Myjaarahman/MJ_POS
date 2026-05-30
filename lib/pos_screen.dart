import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async'; 
import 'payment_screen.dart'; 
import 'add_product_screen.dart';
import 'receipts_screen.dart';
import 'kitchen_screen.dart'; 
import 'printer_service.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- DATA VARIABLES ---
  List<Map<String, dynamic>> _cart = [];
  int? _selectedWaitingNumber;
  final TextEditingController _waitingNumberController = TextEditingController();
  
  // Real-Time Orders & Busy Numbers
  List<Map<String, dynamic>> _activeOrders = [];
  List<int> _unavailableNumbers = []; 
  StreamSubscription? _orderSubscription; 

  // --- CATEGORY VARIABLES ---
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId; 
  String _selectedCategoryName = "All items";
  
  // Business Info
  String _businessName = "MJ POS";
  String _role = "Cashier"; 

  // --- THEME COLORS ---
  final Color _brandBrown = const Color(0xFFC05A17); 
  final Color _bgBeige = const Color(0xFFFDF8EE); 
  final Color _cardWhite = Colors.white;

  @override
  void initState() {
    super.initState();
    _subscribeToOrders(); 
    _fetchBusinessInfo();
    _fetchCategories(); 
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    _waitingNumberController.dispose();
    super.dispose();
  }

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

  Stream<List<Map<String, dynamic>>> _getProductsStream() {
    if (_selectedCategoryId == null) {
      return supabase.from('products').stream(primaryKey: ['id']).order('name');
    } else {
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
            final active = data.where((o) => o['status'] == 'pending' || o['status'] == 'cooking' || o['status'] == 'ready').toList();
            active.sort((a, b) => DateTime.parse(a['created_at']).compareTo(DateTime.parse(b['created_at'])));
            
            setState(() {
              _activeOrders = active;
              _unavailableNumbers = active.map((order) => order['waiting_number'] as int).toList()..sort(); 
            });
          }
        });
  }

  Future<void> _showOrderDetails(Map<String, dynamic> order) async {
    final response = await supabase.from('order_items').select().eq('order_id', order['id']);
    final items = List<Map<String, dynamic>>.from(response);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Order #${order['waiting_number']}", style: const TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text(order['status'].toString().toUpperCase(), style: TextStyle(fontSize: 12, color: Colors.orange.shade900, fontWeight: FontWeight.bold)),
              )
            ],
          ),
          content: SizedBox(
            width: 350,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Text("${item['quantity']}x", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  title: Text(item['product_name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: item['notes'] != null && item['notes'].toString().isNotEmpty
                      ? Text("Note: ${item['notes']}", style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic))
                      : null,
                );
              },
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.print, color: Colors.blue),
              label: const Text("Print", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.blue.shade200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
              ),
              onPressed: () async {
                List<Map<String, dynamic>> mappedCart = items.map((item) {
                  return {
                    'name': item['product_name'],
                    'qty': item['quantity'],
                    'price': item['price_at_sale'],
                    'notes': item['notes'] ?? '', 
                  };
                }).toList();

                try {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Sending to printer..."), duration: Duration(seconds: 1)),
                  );

                  await PrinterService().printOrderReceipt(
                    cart: mappedCart,
                    total: (order['total_amount'] as num).toDouble(),
                    waitingNumber: order['waiting_number'],
                    paymentMethod: order['payment_method'] ?? 'cash',
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Printer Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close", style: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text("Clear", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                  ),
                  onPressed: () async {
                    try {
                      await supabase.from('orders').update({'status': 'completed'}).eq('id', order['id']);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Order cleared!"), backgroundColor: Colors.green));
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                      }
                    }
                  },
                ),
              ],
            )
          ],
        );
      }
    );
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
                        icon: Icon(Icons.add_circle, color: _brandBrown),
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
                  style: ElevatedButton.styleFrom(backgroundColor: _brandBrown),
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

  void _clearCart() {
    setState(() {
      _cart.clear();
      _selectedWaitingNumber = null;
      _waitingNumberController.clear();
    });
  }

  double get _totalAmount => _cart.fold(0, (sum, item) => sum + (item['price'] * item['qty']));

  void _autoPickNumber() {
    for (int i = 1; i <= 18; i++) {
      if (!_unavailableNumbers.contains(i)) {
        setState(() {
          _selectedWaitingNumber = i;
          _waitingNumberController.text = i.toString();
        });
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All numbers 1-18 are full!")));
  }

  String _getAvailableNumbersString() {
    List<int> available = [];
    for (int i = 1; i <= 18; i++) {
      if (!_unavailableNumbers.contains(i)) available.add(i);
    }
    return available.join(', ');
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
      _clearCart();
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: _brandBrown),
            accountName: Text(_businessName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            accountEmail: Text("POS Station • $_role", style: const TextStyle(color: Colors.white70)),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.store, color: Colors.brown)),
          ),
          ListTile(
            leading: const Icon(Icons.kitchen, color: Colors.grey),
            title: const Text("Kitchen Display", style: TextStyle(color: Colors.black)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const KitchenScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.inventory, color: Colors.grey),
            title: const Text("Back Office", style: TextStyle(color: Colors.black)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AddProductScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("Logout", style: TextStyle(color: Colors.red)),
            onTap: () async {
              await supabase.auth.signOut();
              if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bgBeige,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: _brandBrown,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Colors.white),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text("$_businessName ☕", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 1)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.receipt_long, color: Colors.brown, size: 18),
              label: const Text("Receipts", style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiptsScreen()));
              },
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _buildCard(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Active Orders", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Expanded(
                        child: _activeOrders.isEmpty
                            ? Text("No active orders.", style: TextStyle(color: Colors.grey.shade600))
                            : ListView.separated(
                                itemCount: _activeOrders.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final order = _activeOrders[index];
                                  Color statusColor = Colors.orange;
                                  if (order['status'] == 'ready') statusColor = Colors.green;
                                  
                                  return Container(
                                    padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8, right: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: statusColor.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        Text("#${order['waiting_number']}", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: statusColor)),
                                        const Spacer(),
                                        Text(order['status'].toString().toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: statusColor, fontSize: 12)),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: Icon(Icons.more_vert, color: statusColor),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showOrderDetails(order),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 5,
              child: _buildCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Menu", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          PopupMenuButton<int?>(
                            offset: const Offset(0, 40),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            color: Colors.white,
                            onSelected: (int? categoryId) {
                              setState(() {
                                _selectedCategoryId = categoryId;
                                _selectedCategoryName = categoryId == null 
                                    ? "All items" 
                                    : _categories.firstWhere((e) => e['id'] == categoryId)['name'];
                              });
                            },
                            itemBuilder: (context) {
                              List<PopupMenuEntry<int?>> list = [
                                const PopupMenuItem(value: null, child: Text("All items", style: TextStyle(fontWeight: FontWeight.bold))),
                                const PopupMenuDivider(),
                              ];
                              for (var cat in _categories) {
                                list.add(PopupMenuItem(value: cat['id'], child: Text(cat['name'])));
                              }
                              return list;
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.filter_list, size: 18, color: Colors.grey.shade700),
                                  const SizedBox(width: 8),
                                  Text(_selectedCategoryName, style: TextStyle(color: Colors.grey.shade900, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 4),
                                  Icon(Icons.keyboard_arrow_down, size: 20, color: Colors.grey.shade700),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _getProductsStream(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                          final products = snapshot.data!;
                          
                          if (products.isEmpty) {
                            return Center(child: Text("No items found.", style: TextStyle(color: Colors.grey.shade500)));
                          }

                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180, 
                              childAspectRatio: 0.85, 
                              crossAxisSpacing: 16, 
                              mainAxisSpacing: 16,
                            ),
                            itemCount: products.length,
                            itemBuilder: (context, index) {
                              final product = products[index];
                              return GestureDetector(
                                onTap: () => _addToCart(product),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white, 
                                    borderRadius: BorderRadius.circular(8), 
                                    border: Border.all(color: Colors.grey.shade200),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: _bgBeige,
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                          ),
                                          child: Center(
                                            child: Icon(Icons.fastfood, size: 40, color: Colors.grey.shade300),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(product['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 4),
                                            Text("RM ${product['price']}", style: TextStyle(color: _brandBrown, fontWeight: FontWeight.bold, fontSize: 14)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: _buildCard(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("Current Order", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _cart.isEmpty 
                        ? Center(child: Text("Tap items to add to order.", style: TextStyle(color: Colors.grey.shade500)))
                        : ListView.separated(
                          itemCount: _cart.length,
                          separatorBuilder: (_,__) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _cart[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap: () => _editCartItem(index), 
                              title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              subtitle: item['notes'] != '' 
                                ? Text(item['notes'], style: const TextStyle(color: Colors.orange, fontSize: 12)) 
                                : null,
                              trailing: Text("RM ${(item['price'] * item['qty']).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                              leading: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                                child: Text("${item['qty']}x", style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _waitingNumberController,
                              decoration: const InputDecoration(
                                labelText: "Waiting Number", 
                                border: OutlineInputBorder(), 
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (val) => setState(() => _selectedWaitingNumber = int.tryParse(val)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _autoPickNumber, 
                              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              child: const Text("Auto\nPick", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black)),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Total", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          Text("RM ${_totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _goToPayment,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _brandBrown,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                child: const Text("Confirm Order", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: SizedBox(
                              height: 50,
                              child: OutlinedButton(
                                onPressed: _clearCart,
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.grey.shade400),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("Clear", style: TextStyle(color: Colors.black, fontSize: 16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}