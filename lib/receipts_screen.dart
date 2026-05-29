import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart'; 
import 'printer_service.dart';

class ReceiptsScreen extends StatefulWidget {
  // Notice there is no 'order' required here! This fixes your crash.
  const ReceiptsScreen({super.key});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  Map<String, dynamic>? _selectedOrder;
  List<Map<String, dynamic>> _orderItems = [];
  bool _isLoadingDetails = false;

  // --- REPRINT RECEIPT LOGIC ---
  Future<void> _reprintReceipt() async {
    if (_selectedOrder == null) return;

    List<Map<String, dynamic>> mappedCart = _orderItems.map((item) {
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
        total: (_selectedOrder!['total_amount'] as num).toDouble(),
        waitingNumber: _selectedOrder!['waiting_number'],
        paymentMethod: _selectedOrder!['payment_method'],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Printer Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

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
      ),
      body: Row(
        children: [
          // --- LEFT SIDE: LIST OF ORDERS (Grouped by Date) ---
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Colors.grey.shade300))),
              child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: supabase.from('orders').stream(primaryKey: ['id']).order('created_at', ascending: false),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final orders = snapshot.data!;

                  if (orders.isEmpty) return const Center(child: Text("No receipts yet"));

                  return ListView.builder(
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final isSelected = _selectedOrder != null && _selectedOrder!['id'] == order['id'];
                      final String currentDateString = _formatDate(order['created_at']);
                      final bool showDateHeader = index == 0 || _formatDate(orders[index - 1]['created_at']) != currentDateString;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDateHeader) ...[
                            if (index != 0) const Divider(height: 1, thickness: 1),
                            Container(
                              color: Colors.grey.shade100,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Text(currentDateString, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700, fontSize: 14)),
                            ),
                          ] else ...[
                            const Divider(height: 1),
                          ],
                          ListTile(
                            selected: isSelected,
                            selectedTileColor: Colors.blue.shade50,
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("RM ${order['total_amount']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text("#${order['waiting_number']}", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                              ],
                            ),
                            subtitle: Text(_formatTime(order['created_at'])),
                            onTap: () => _fetchOrderDetails(order),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // --- RIGHT SIDE: POLISHED RECEIPT UI ---
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
                          child: SingleChildScrollView(
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // --- THE ELEGANT RECEIPT CARD ---
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4))],
                                      border: Border.all(color: Colors.grey.shade100, width: 1),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          // Header
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
                                            child: Column(
                                              children: [
                                                const Text('H&S CHOICES', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Color(0xFF1A1A1A))),
                                                const SizedBox(height: 4),
                                                Text('LAMAN KAK MISAI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: Colors.grey.shade500)),
                                                const SizedBox(height: 24),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text('ORDER NO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade400, letterSpacing: 0.5)),
                                                        const SizedBox(height: 2),
                                                        Text('#${_selectedOrder!['waiting_number']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                                                      ],
                                                    ),
                                                    Column(
                                                      crossAxisAlignment: CrossAxisAlignment.end,
                                                      children: [
                                                        Text('DATE & TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade400, letterSpacing: 0.5)),
                                                        const SizedBox(height: 2),
                                                        Text('${_formatDate(_selectedOrder!['created_at'])}, ${_formatTime(_selectedOrder!['created_at'])}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Divider(color: Colors.grey.shade200, thickness: 1, height: 1)),
                                          
                                          // Items List
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                                            child: Column(
                                              children: _orderItems.map((item) {
                                                final double itemTotal = (double.tryParse(item['price_at_sale'].toString()) ?? 0.0) * (item['quantity'] as int);
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text('${item['quantity']}x', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
                                                          const SizedBox(width: 12),
                                                          Expanded(child: Text(item['product_name'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2D2D2D)))),
                                                          const SizedBox(width: 8),
                                                          Text('RM ${itemTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A))),
                                                        ],
                                                      ),
                                                      if (item['notes'] != null && item['notes'].toString().isNotEmpty)
                                                        Padding(
                                                          padding: const EdgeInsets.only(left: 32, top: 4),
                                                          child: Text('• ${item['notes']}', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.red.shade600, fontWeight: FontWeight.w500)),
                                                        ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                          
                                          // Footer Total
                                          Container(
                                            color: Colors.grey.shade50,
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                              children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    const Text('TOTAL AMOUNT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF7D7D7D), letterSpacing: 0.5)),
                                                    Text('RM ${double.parse(_selectedOrder!['total_amount'].toString()).toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                                                  ],
                                                ),
                                                const SizedBox(height: 16),
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(30)),
                                                      child: Text(_selectedOrder!['payment_method'].toString().toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Colors.indigo.shade700)),
                                                    ),
                                                    Text('TRANSACTION SUCCESS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade400, letterSpacing: 0.5)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(height: 24),
                                  
                                  // --- REPRINT BUTTON ---
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.print),
                                      label: const Text("Reprint Receipt", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue.shade700,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                      onPressed: _reprintReceipt,
                                    ),
                                  ),
                                ],
                              ),
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