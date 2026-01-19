import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async'; // For the timer

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Kitchen Display System", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          // Filter Legend
          _buildLegendDot(Colors.grey, "New"),
          _buildLegendDot(Colors.orange, "Cooking"),
          _buildLegendDot(Colors.green, "Ready"),
          const SizedBox(width: 20),
        ],
      ),
      body: Container(
        color: const Color(0xFFF5F5F5), // Light grey background
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<List<Map<String, dynamic>>>(
          // Listen to orders that are NOT completed
          stream: supabase
              .from('orders')
              .stream(primaryKey: ['id'])
              .order('created_at', ascending: true), // Oldest orders first!
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            
            // Filter out 'completed' orders locally (since stream filter is limited)
            final orders = snapshot.data!.where((o) => o['status'] != 'completed').toList();

            if (orders.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 80, color: Colors.grey.shade300),
                    const SizedBox(height: 20),
                    Text("All caught up!", style: TextStyle(fontSize: 24, color: Colors.grey.shade400)),
                  ],
                ),
              );
            }

            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 350, // Width of each ticket
                childAspectRatio: 0.75, // Taller tickets
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                return KitchenOrderCard(order: orders[index]);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: color, radius: 5),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.black)),
        ],
      ),
    );
  }
}

// --- INDIVIDUAL ORDER CARD WIDGET ---
// --- INDIVIDUAL ORDER CARD WIDGET ---
class KitchenOrderCard extends StatefulWidget {
  final Map<String, dynamic> order;

  const KitchenOrderCard({super.key, required this.order});

  @override
  State<KitchenOrderCard> createState() => _KitchenOrderCardState();
}

class _KitchenOrderCardState extends State<KitchenOrderCard> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  bool _isLoadingItems = true;
  late Timer _timer;
  String _timeElapsed = "";

  @override
  void initState() {
    super.initState();
    _fetchItems();
    _startTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startTimer() {
    _updateTime(); 
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _updateTime();
    });
  }

  void _updateTime() {
    final created = DateTime.parse(widget.order['created_at']).toLocal();
    final diff = DateTime.now().difference(created);
    setState(() {
      _timeElapsed = "${diff.inMinutes}m ago";
    });
  }

  Future<void> _fetchItems() async {
    final response = await supabase
        .from('order_items')
        .select()
        .eq('order_id', widget.order['id']);
    
    if (mounted) {
      setState(() {
        _items = List<Map<String, dynamic>>.from(response);
        _isLoadingItems = false;
      });
    }
  }

  // --- UPDATED LOGIC FOR INSTANT REMOVAL ---
  Future<void> _advanceStatus() async {
    String nextStatus = 'cooking';
    String current = widget.order['status'];

    if (current == 'pending') nextStatus = 'cooking';
    else if (current == 'cooking') nextStatus = 'ready';
    else if (current == 'ready') nextStatus = 'completed'; // This triggers removal

    // 1. INSTANTLY Update Local State (Optimistic UI)
    setState(() {
      widget.order['status'] = nextStatus;
    });

    // 2. Send Update to Database
    try {
      await supabase.from('orders').update({'status': nextStatus}).eq('id', widget.order['id']);
    } catch (e) {
      // Revert if error
      setState(() => widget.order['status'] = current);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Color _getStatusColor() {
    switch (widget.order['status']) {
      case 'cooking': return Colors.orange;
      case 'ready': return Colors.green;
      default: return Colors.grey;
    }
  }

  String _getButtonText() {
    switch (widget.order['status']) {
      case 'pending': return "START COOKING";
      case 'cooking': return "MARK READY";
      case 'ready': return "COMPLETE (CLEAR)";
      default: return "Wait";
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- THE INVISIBILITY CLOAK ---
    // If the status is 'completed', hide this widget immediately!
    if (widget.order['status'] == 'completed') {
      return const SizedBox.shrink();
    }
    // -----------------------------

    final statusColor = _getStatusColor();
    final bool isReady = widget.order['status'] == 'ready';

    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor, width: 2),
      ),
      child: Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "#${widget.order['waiting_number']}",
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_timeElapsed, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(widget.order['status'].toString().toUpperCase(), style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
                  ],
                )
              ],
            ),
          ),

          // ITEMS LIST
          Expanded(
            child: _isLoadingItems
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final hasNote = item['notes'] != null && item['notes'].toString().isNotEmpty;
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(4)
                                ),
                                child: Text("${item['quantity']}x", style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item['product_name'], 
                                  style: const TextStyle(fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (hasNote)
                            Padding(
                              padding: const EdgeInsets.only(left: 40.0, top: 4),
                              child: Text(
                                "Note: ${item['notes']}", 
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),

          // FOOTER BUTTON
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _advanceStatus,
              style: ElevatedButton.styleFrom(
                backgroundColor: isReady ? Colors.green : statusColor,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
                ),
                elevation: 0,
              ),
              child: Text(
                _getButtonText(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}