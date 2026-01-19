import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  
  // -- CONTROLLERS FOR PRODUCT --
  final _productFormKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  int? _selectedCategoryId;

  // -- CONTROLLERS FOR CATEGORY --
  final _categoryFormKey = GlobalKey<FormState>();
  final _categoryNameController = TextEditingController();

  // Data
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCategories();
  }

  // 1. Fetch Categories
  Future<void> _loadCategories() async {
    final response = await supabase.from('categories').select();
    if (mounted) {
      setState(() {
        _categories = List<Map<String, dynamic>>.from(response);
      });
    }
  }

  // 2. Get Business ID
  Future<String?> _getMyBusinessId() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    final profile = await supabase.from('profiles').select('business_id').eq('id', user.id).single();
    return profile['business_id'];
  }

  // 3. Submit Product
  Future<void> _submitProduct() async {
    if (_productFormKey.currentState!.validate() && _selectedCategoryId != null) {
      setState(() => _isLoading = true);

      try {
        final businessId = await _getMyBusinessId();
        final int stock = _stockController.text.isEmpty ? 0 : int.parse(_stockController.text);

        await supabase.from('products').insert({
          'name': _nameController.text,
          'price': double.parse(_priceController.text),
          'stock_quantity': stock,
          'category_id': _selectedCategoryId,
          'business_id': businessId,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Added!'), backgroundColor: Colors.green));
          _nameController.clear();
          _priceController.clear();
          _stockController.clear();
          // We keep the category selected for convenience
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a category'), backgroundColor: Colors.red));
    }
  }

  // 4. Submit Category
  Future<void> _submitCategory() async {
    if (_categoryFormKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final businessId = await _getMyBusinessId();
        await supabase.from('categories').insert({'name': _categoryNameController.text, 'business_id': businessId});
        await _loadCategories(); // Refresh list

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category Created!'), backgroundColor: Colors.green));
          _categoryNameController.clear();
          _tabController.animateTo(0); // Switch to Product tab
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // 5. Delete Category
  Future<void> _deleteCategory(int id) async {
    try {
      await supabase.from('categories').delete().eq('id', id);
      await _loadCategories();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category Deleted!'), backgroundColor: Colors.red));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete: Remove products in this category first.'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  // 6. Delete Product (FIXED)
  Future<void> _deleteProduct(int id) async {
    try {
      await supabase.from('products').delete().eq('id', id);
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Deleted'), backgroundColor: Colors.red));
         setState(() {}); // Refresh the UI
      }
    } catch (e) {
      // This catches the error if the product has already been sold
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot delete: This product is part of past orders.'), 
            backgroundColor: Colors.orange
          ),
        );
      }
    }
  }

  // 7. Edit Product Dialog
  void _showEditProductDialog(Map<String, dynamic> product) {
    final nameCtrl = TextEditingController(text: product['name']);
    final priceCtrl = TextEditingController(text: product['price'].toString());
    
    showDialog(
      context: context, 
      builder: (context) => AlertDialog(
        title: const Text("Edit Product"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name")),
            TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: "Price")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await supabase.from('products').update({
                'name': nameCtrl.text,
                'price': double.parse(priceCtrl.text),
              }).eq('id', product['id']);
              
              if (mounted) Navigator.pop(context);
            }, 
            child: const Text("Save Changes")
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Back Office"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.shopping_bag), text: "Manage Products"),
            Tab(icon: Icon(Icons.category), text: "Manage Categories"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // --- TAB 1: ADD & LIST PRODUCTS ---
          Column(
            children: [
              // A. THE FORM (Always Visible Now)
              Container(
                padding: const EdgeInsets.all(16.0),
                color: Colors.white,
                child: Form(
                  key: _productFormKey,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(labelText: 'Product Name', isDense: true),
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _priceController,
                              decoration: const InputDecoration(labelText: 'Price', isDense: true),
                              keyboardType: TextInputType.number,
                              validator: (v) => v!.isEmpty ? 'Required' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _stockController,
                              decoration: const InputDecoration(labelText: 'Stock (Optional)', isDense: true),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _selectedCategoryId,
                              hint: const Text("Category"),
                              items: _categories.map((cat) => DropdownMenuItem<int>(
                                value: cat['id'], child: Text(cat['name'])
                              )).toList(),
                              onChanged: (val) => setState(() => _selectedCategoryId = val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitProduct,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          child: const Text("Add New Product"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const Divider(thickness: 5, color: Colors.grey),

              // B. THE LIST (Realtime)
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: supabase.from('products').stream(primaryKey: ['id']), 
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final products = snapshot.data!;
                    if (products.isEmpty) return const Center(child: Text("No products yet."));

                    return ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return ListTile(
                          title: Text(product['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("Price: RM ${product['price']} | Stock: ${product['stock_quantity']}"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _showEditProductDialog(product),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteProduct(product['id']),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),

          // --- TAB 2: MANAGE CATEGORIES ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Form(
                  key: _categoryFormKey,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _categoryNameController,
                          decoration: const InputDecoration(labelText: 'New Category Name', border: OutlineInputBorder(), isDense: true),
                          validator: (v) => v!.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _submitCategory,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
                        child: const Text("Add"),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text("Existing Categories", style: TextStyle(fontWeight: FontWeight.bold)),
                const Divider(),
                Expanded(
                  child: ListView.separated(
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: Colors.orange.shade100, child: Text(cat['name'][0], style: const TextStyle(color: Colors.orange))),
                        title: Text(cat['name']),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteCategory(cat['id']),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}