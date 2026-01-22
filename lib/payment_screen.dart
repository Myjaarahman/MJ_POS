import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentScreen extends StatefulWidget {
  final List<Map<String, dynamic>> cart;
  final double totalAmount;
  final int waitingNumber;

  const PaymentScreen({
    super.key,
    required this.cart,
    required this.totalAmount,
    required this.waitingNumber,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _cashController = TextEditingController();
  double _changeDue = 0.0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _cashController.addListener(() {
      final cash = double.tryParse(_cashController.text) ?? 0.0;
      setState(() {
        _changeDue = cash - widget.totalAmount;
      });
    });
  }

  void _addCash(double amount) {
    final current = double.tryParse(_cashController.text) ?? 0.0;
    _cashController.text = (current + amount).toStringAsFixed(2);
  }

  // UPDATED: Now accepts 'cash' or 'card'
  Future<void> _finalizeOrder(String paymentType) async {
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      
      // 1. Get Business ID
      final profile = await supabase.from('profiles').select('business_id').eq('id', user!.id).single();
      final businessId = profile['business_id'];

      // 2. Create Order with correct PAYMENT METHOD
      final orderResponse = await supabase.from('orders').insert({
        'total_amount': widget.totalAmount,
        'status': 'pending', 
        'staff_id': user.id,
        'business_id': businessId,
        'waiting_number': widget.waitingNumber,
        'order_number': 'ORD-${DateTime.now().millisecondsSinceEpoch}',
        'payment_method': paymentType, // <--- SAVES 'cash' or 'card' HERE
      }).select().single();

      final orderId = orderResponse['id'];

      // 3. Create Order Items
      for (var item in widget.cart) {
        await supabase.from('order_items').insert({
          'order_id': orderId,
          'product_id': item['id'],
          'product_name': item['name'],
          'quantity': item['qty'],
          'price_at_sale': item['price'],
          'notes': item['notes'] ?? '',
        });
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Return "true" to clear cart
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Paid via ${paymentType.toUpperCase()} - Sent to Kitchen!"), 
            backgroundColor: Colors.green
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- LIGHT THEME COLORS ---
    const bgColor = Colors.white;
    final cardColor = Colors.grey.shade100; // Very light grey for buttons
    const textColor = Colors.black;
    final dividerColor = Colors.grey.shade300;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        // Title and Icon are black to be visible on white
        title: const Text("Payment", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: textColor),
      ),
      body: Row(
        children: [
          // LEFT SIDE: Ticket Summary
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: dividerColor)),
              ),
              child: Column(
                children: [
                  Text("Waiting No: ${widget.waitingNumber}", style: const TextStyle(color: Colors.orange, fontSize: 24, fontWeight: FontWeight.bold)),
                  Divider(color: dividerColor),
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.cart.length,
                      itemBuilder: (context, index) {
                        final item = widget.cart[index];
                        return ListTile(
                          title: Text(item['name'], style: const TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                          subtitle: item['notes'] != null && item['notes'].isNotEmpty 
                              ? Text("Note: ${item['notes']}", style: const TextStyle(color: Colors.grey)) 
                              : null,
                          trailing: Text("RM ${(item['price'] * item['qty']).toStringAsFixed(2)}", style: const TextStyle(color: textColor)),
                          leading: Text("${item['qty']}x", style: const TextStyle(color: textColor)),
                        );
                      },
                    ),
                  ),
                  Divider(color: dividerColor),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("TOTAL", style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
                      Text("RM ${widget.totalAmount.toStringAsFixed(2)}", style: const TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // RIGHT SIDE: Payment Inputs
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   Center(
                    child: Column(
                      children: [
                        const Text("Total Amount Due", style: TextStyle(color: Colors.grey)),
                        Text("RM ${widget.totalAmount.toStringAsFixed(2)}", style: const TextStyle(color: textColor, fontSize: 48, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Row for Input + Charge Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cashController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: textColor, fontSize: 24),
                          decoration: const InputDecoration(
                            labelText: "Cash Received",
                            labelStyle: TextStyle(color: Colors.grey),
                            prefixText: "RM ",
                            prefixStyle: TextStyle(color: textColor, fontSize: 24),
                            // Line color for white background
                            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.blueGrey, width: 2)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // CHARGE BUTTON (FOR CASH)
                      SizedBox(
                        height: 50,
                        width: 120,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : () => _finalizeOrder('cash'), // Sends 'cash'
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            foregroundColor: Colors.white, // Text color
                          ),
                          child: _isLoading 
                            ? const CircularProgressIndicator(color: Colors.white) 
                            : const Text("CHARGE", style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Quick Cash Buttons
                  Wrap(
                    spacing: 10,
                    children: [5.0, 10.0, 50.0, 100.0].map((amount) {
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cardColor, // Light Grey
                          foregroundColor: textColor, // Black text
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: dividerColor) // Subtle border
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 25),
                        ),
                        onPressed: () => _addCash(amount),
                        child: Text("RM ${amount.toInt()}"),
                      );
                    }).toList(),
                  ),

                  // Change Display
                  if (_changeDue > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          "Change: RM ${_changeDue.toStringAsFixed(2)}",
                          style: const TextStyle(color: Colors.green, fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  
                  const Spacer(),

                  // QR PAYMENT BUTTON (Full Width at Bottom)
                  SizedBox(
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _finalizeOrder('card'), // Sends 'card'
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black87, // Dark background for contrast
                        foregroundColor: Colors.white, // White text
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        )
                      ),
                      icon: const Icon(Icons.qr_code, color: Colors.white),
                      label: const Text("QR PAYMENT", style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}