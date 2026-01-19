import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; // You might need to add intl package to pubspec.yaml

class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  Map<String, dynamic>? _selectedOrder;
  List<Map<String, dynamic>> _orderItems = [];
  bool _isLoadingDetails = false;

  // Fetch Items when an order is clicked
  Future<void> _fetchOrderDetails(Map<String, dynamic> order) async {
    setState(() {
      _selectedOrder = order;
      _isLoadingDetails = true;
    });

    final response = await supabase
        .from('order_items')
        .select()
        .eq('order_id', order['id']);

    if (mounted) {
      setState(() {
        _orderItems = List<Map<String, dynamic>>.from(response);
        _isLoadingDetails = false;
      });
    }
  }

  // Helper to format date
  String _formatDate(String dateString) {
    final date = DateTime.parse(dateString).toLocal();
    return DateFormat('EEE, d MMM yyyy').format(date);
  }
  
  String _formatTime(String dateString) {
    final date = DateTime.parse(dateString).toLocal();
    return DateFormat('h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Receipts", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Row(
        children: [
          // --- LEFT SIDE: LIST OF ORDERS ---
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.grey.shade300)),
              ),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: supabase
                    .from('orders')
                    .stream(primaryKey: ['id'])
                    .order('created_at', ascending: false),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final orders = snapshot.data!;

                  if (orders.isEmpty) return const Center(child: Text("No receipts yet"));

                  return ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final isSelected = _selectedOrder != null && _selectedOrder!['id'] == order['id'];

                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: Colors.blue.shade50,
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "RM ${order['total_amount']}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              "#${order['waiting_number']}",
                              style: const TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ],
                        ),
                        subtitle: Text(_formatTime(order['created_at'])),
                        onTap: () => _fetchOrderDetails(order),
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // --- RIGHT SIDE: RECEIPT DETAILS ---
          Expanded(
            flex: 6,
            child: _selectedOrder == null
                ? const Center(child: Text("Select a receipt to view details", style: TextStyle(color: Colors.grey)))
                : _isLoadingDetails
                    ? const Center(child: CircularProgressIndicator())
                    : Container(
                        color: Colors.grey.shade50,
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 400),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // HEADER
                                Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        "RM ${_selectedOrder!['total_amount']}",
                                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                      ),
                                      const Text("Total", style: TextStyle(color: Colors.grey)),
                                      const SizedBox(height: 20),
                                      const Divider(),
                                      const SizedBox(height: 10),
                                      Text("Date: ${_formatDate(_selectedOrder!['created_at'])} ${_formatTime(_selectedOrder!['created_at'])}"),
                                      Text("Waiting No: ${_selectedOrder!['waiting_number']}"),
                                      Text("Payment: ${_selectedOrder!['payment_method'].toString().toUpperCase()}"),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Divider(),
                                
                                // ITEMS LIST
                                ..._orderItems.map((item) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item['product_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Text("${item['quantity']} x RM ${item['price_at_sale']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                        ],
                                      ),
                                      Text("RM ${(item['price_at_sale'] * item['quantity']).toStringAsFixed(2)}"),
                                    ],
                                  ),
                                )),

                                const Divider(),
                                const SizedBox(height: 10),
                                
                                // FOOTER
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Total", style: TextStyle(fontWeight: FontWeight.bold)),
                                    Text("RM ${_selectedOrder!['total_amount']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_selectedOrder!['payment_method'].toString().toUpperCase(), style: const TextStyle(color: Colors.grey)),
                                    Text("RM ${_selectedOrder!['total_amount']}", style: const TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ],
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