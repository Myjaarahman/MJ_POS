import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pos_screen.dart';
import 'kitchen_screen.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- DESIGN SYSTEM COLORS ---
  final Color _brandBrown = const Color(0xFFC05A17); 
  final Color _bgBeige = const Color(0xFFFDF8EE); 
  final Color _cardWhite = Colors.white;

  // --- STATE VARIABLES ---
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  String _businessName = "MJ POS";
  String _role = "Admin";

  // Form Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  int? _selectedCategoryId;
  String? _editingProductId; // If null, we are adding. If set, we are editing.

  @override
  void initState() {
    super.initState();
    _fetchBusinessInfo();
    _fetchCategoriesAndProducts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _fetchBusinessInfo() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final profile = await supabase.from('profiles').select('business_id, role').eq('id', user.id).single();
      setState(() => _role = profile['role'].toString().toUpperCase());
      
      if (profile['business_id'] != null) {
        final business = await supabase.from('businesses').select('name').eq('id', profile['business_id']).single();
        if (mounted) setState(() => _businessName = business['name']);
      }
    } catch (e) {
      debugPrint("Error fetching business info: $e");
    }
  }

  Future<void> _fetchCategoriesAndProducts() async {
    setState(() => _isLoading = true);
    try {
      final catResponse = await supabase.from('categories').select().order('name');
      final prodResponse = await supabase.from('products').select().order('name');
      
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(catResponse);
          _products = List<Map<String, dynamic>>.from(prodResponse);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching data: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- FORM ACTIONS ---
  void _startEditing(Map<String, dynamic> product) {
    setState(() {
      _editingProductId = product['id'].toString();
      _nameController.text = product['name'];
      _priceController.text = product['price'].toString();
      _selectedCategoryId = product['category_id'];
    });
  }

  void _clearForm() {
    setState(() {
      _editingProductId = null;
      _nameController.clear();
      _priceController.clear();
      _selectedCategoryId = null;
    });
  }

  Future<void> _saveProduct() async {
    // FIX 1: Force the iPad keyboard to close immediately
    FocusScope.of(context).unfocus(); 

    // FIX 2: Automatically swap any commas for decimals so Bluefy doesn't break
    String safePrice = _priceController.text.replaceAll(',', '.').trim();

    if (_nameController.text.isEmpty || safePrice.isEmpty || _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields"), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final productData = {
        'name': _nameController.text.trim(),
        'price': double.tryParse(safePrice) ?? 0.0, // Uses the safe price here
        'category_id': _selectedCategoryId,
      };

      if (_editingProductId == null) {
        // ADD NEW
        await supabase.from('products').insert(productData);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product Added!"), backgroundColor: Colors.green));
      } else {
        // UPDATE EXISTING
        await supabase.from('products').update(productData).eq('id', _editingProductId!);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product Updated!"), backgroundColor: Colors.blue));
      }
      
      _clearForm();
      await _fetchCategoriesAndProducts();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteProduct(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Product?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Delete", style: TextStyle(color: Colors.white))
          ),
        ],
      )
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await supabase.from('products').delete().eq('id', id);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product Deleted"), backgroundColor: Colors.red));
        await _fetchCategoriesAndProducts();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
      }
    }
  }

  // --- UI COMPONENTS ---
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.white,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: _brandBrown),
            accountName: Text(_businessName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            accountEmail: Text("Back Office • $_role", style: const TextStyle(color: Colors.white70)),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.inventory, color: Colors.brown)),
          ),
          ListTile(
            leading: const Icon(Icons.point_of_sale, color: Colors.grey),
            title: const Text("POS System", style: TextStyle(color: Colors.black)),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const PosScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.kitchen, color: Colors.grey),
            title: const Text("Kitchen Display", style: TextStyle(color: Colors.black)),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const KitchenScreen()));
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
        border: Border.all(color: Colors.grey.shade100, width: 1),
      ),
      child: child,
    );
  }

  String _getCategoryName(int id) {
    try {
      return _categories.firstWhere((c) => c['id'] == id)['name'];
    } catch (e) {
      return "Unknown";
    }
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
        leading: IconButton(icon: const Icon(Icons.menu, color: Colors.white), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
        title: const Text("Inventory Management", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                
                // --- LEFT COLUMN: PRODUCT FORM ---
                Expanded(
                  flex: 3,
                  child: _buildCard(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(_editingProductId == null ? Icons.add_circle : Icons.edit, color: _brandBrown, size: 28),
                              const SizedBox(width: 12),
                              Text(
                                _editingProductId == null ? "Add New Product" : "Edit Product", 
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          
                          // Form Fields
                          Text("PRODUCT NAME", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              hintText: "e.g., Iced Spanish Latte",
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _brandBrown, width: 2)),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          Text("PRICE (RM)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _priceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              hintText: "0.00",
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: _brandBrown, width: 2)),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          Text("CATEGORY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600, letterSpacing: 0.5)),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _selectedCategoryId,
                                hint: const Text("Select a category"),
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down),
                                items: _categories.map((cat) {
                                  return DropdownMenuItem<int>(
                                    value: cat['id'],
                                    child: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _selectedCategoryId = val),
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),
                          
                          // Action Buttons
                          SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _brandBrown,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _saveProduct,
                              child: Text(_editingProductId == null ? "Save Product" : "Update Product", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          if (_editingProductId != null) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 54,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.grey.shade300),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: _clearForm,
                                child: const Text("Cancel Edit", style: TextStyle(fontSize: 16, color: Colors.black)),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 24),

                // --- RIGHT COLUMN: INVENTORY LIST ---
                Expanded(
                  flex: 5,
                  child: _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Current Inventory", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(20)),
                                child: Text("${_products.length} Items", style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                              )
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        
                        Expanded(
                          child: _products.isEmpty 
                            ? Center(child: Text("No products found.", style: TextStyle(color: Colors.grey.shade500)))
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: _products.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final product = _products[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    leading: Container(
                                      height: 48, width: 48,
                                      decoration: BoxDecoration(color: _bgBeige, borderRadius: BorderRadius.circular(8)),
                                      child: Icon(Icons.fastfood, color: _brandBrown.withOpacity(0.5)),
                                    ),
                                    title: Text(product['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF2D2D2D))),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
                                            child: Text(
                                              _getCategoryName(product['category_id']).toUpperCase(), 
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.indigo.shade700)
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text("RM ${product['price']}", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1A1A1A))),
                                        const SizedBox(width: 24),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                                          tooltip: "Edit Product",
                                          onPressed: () => _startEditing(product),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                                          tooltip: "Delete Product",
                                          onPressed: () => _deleteProduct(product['id'].toString()),
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
              ],
            ),
          ),
    );
  }
}