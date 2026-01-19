import 'package:supabase_flutter/supabase_flutter.dart';

class ProductService {
  final SupabaseClient supabase = Supabase.instance.client;

  // 1. Fetch Categories for the Dropdown
  Future<List<Map<String, dynamic>>> getCategories() async {
    final response = await supabase.from('categories').select();
    return List<Map<String, dynamic>>.from(response);
  }

  // 2. Add the Product to Supabase
  Future<void> addProduct({
    required String name,
    required double price,
    required int stock,
    required int categoryId,
  }) async {
    await supabase.from('products').insert({
      'name': name,
      'price': price,
      'stock_quantity': stock,
      'category_id': categoryId, 
    });
  }
}