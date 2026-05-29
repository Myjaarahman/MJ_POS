import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:intl/intl.dart'; // Required for formatting the current Date

class PrinterService {
  static const String targetDeviceName = "9printer-58B"; 

  // --- STICKY MEMORY VARIABLES ---
  static BluetoothDevice? _connectedDevice;
  static BluetoothCharacteristic? _writeCharacteristic;

  // The UUIDs required by Web Bluetooth security
  final List<Guid> commonPrinterServices = [
    Guid("49535343-fe7d-4ae5-8fa9-9fafd205e455"), 
    Guid("e7810a71-73ae-499d-8c15-faa9aef0c3f2"), 
    Guid("000018f0-0000-1000-8000-00805f9b34fb"), 
  ];

  Future<void> printOrderReceipt({
    required List<Map<String, dynamic>> cart,
    required double total,
    required int waitingNumber,
    required String paymentMethod,
  }) async {
    
    // 1. CHECK MEMORY: If not connected, scan and ask for permission
    if (_writeCharacteristic == null || _connectedDevice == null || _connectedDevice!.isConnected == false) {
      await _scanAndConnect();
    }

    // If they canceled the popup or the printer is off, abort safely.
    if (_writeCharacteristic == null) {
      print("Printer not found or user canceled connection.");
      return; 
    }

    // 2. GENERATE RECEIPT
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      // Format the current date (e.g. "29 May 2026, 10:56 PM")
      String currentDate = DateFormat('dd MMM yyyy, h:mm a').format(DateTime.now());

      // --- TICKET HEADER ---
      bytes += generator.text('H&S Choices', styles: const PosStyles(align: PosAlign.center, bold: true, width: PosTextSize.size2, height: PosTextSize.size2));
      
      // Address (Split to fit 32-character limit beautifully)
      bytes += generator.text('LAMAN KAK MISAI, 224,', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('Kampung Parit Keroma Darat,', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('84000 Muar, Johor', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);
      
      // Contacts
      bytes += generator.text('Hapiz: +60 17-648 5034', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('Sofia: +60 17-648 5374', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);
      
      // Date and Order Number
      bytes += generator.text('Date: $currentDate', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('Order No: $waitingNumber', styles: const PosStyles(align: PosAlign.center, bold: true, width: PosTextSize.size2, height: PosTextSize.size2));
      bytes += generator.feed(1);
      bytes += generator.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));

      // --- CART ITEMS ---
      for (var item in cart) {
        String itemName = item['name'];
        int qty = item['qty'];
        double price = item['price'] * qty;
        
        bytes += generator.row([
          PosColumn(text: '${qty}x $itemName', width: 8, styles: const PosStyles(align: PosAlign.left)),
          PosColumn(text: price.toStringAsFixed(2), width: 4, styles: const PosStyles(align: PosAlign.right)),
        ]);
        
        if (item['notes'] != null && item['notes'].toString().isNotEmpty) {
           bytes += generator.text('   ** ${item['notes']}', styles: const PosStyles(align: PosAlign.left));
        }
      }

      // --- FOOTER ---
      bytes += generator.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.row([
        PosColumn(text: 'TOTAL:', width: 6, styles: const PosStyles(align: PosAlign.left, bold: true)),
        PosColumn(text: 'RM ${total.toStringAsFixed(2)}', width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
      bytes += generator.text('PAID VIA: ${paymentMethod.toUpperCase()}', styles: const PosStyles(align: PosAlign.left));
      
      // Final whitespace and auto-cut
      bytes += generator.feed(2);
      bytes += generator.cut();

      // 3. SEND TO PRINTER 
      await _writeCharacteristic!.write(bytes, withoutResponse: true);
      print("Print successful!");

    } catch (e) {
      print("Printer disconnected or error: $e");
      // If it fails (e.g., the printer was turned off), clear memory so it asks again next time.
      _connectedDevice = null;
      _writeCharacteristic = null;
    }
  }

// --- INTERNAL HELPER TO SCAN & CONNECT ---
  Future<void> _scanAndConnect() async {
    print("Starting new scan...");
    
    // THE FIX: We removed 'withServices' and added 'withNames'.
    // Now the iPad will look for the exact name of the printer instead 
    // of relying on the hidden Bluetooth IDs!
    await FlutterBluePlus.startScan(
      withNames: [targetDeviceName], 
      timeout: const Duration(seconds: 4)
    );
    
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == targetDeviceName || r.device.advName == targetDeviceName) {
          _connectedDevice = r.device;
          FlutterBluePlus.stopScan();
          break;
        }
      }
    });

    await Future.delayed(const Duration(seconds: 4));
    await subscription.cancel();

    if (_connectedDevice != null) {
      await _connectedDevice!.connect();
      List<BluetoothService> services = await _connectedDevice!.discoverServices();
      
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.properties.writeWithoutResponse || characteristic.properties.write) {
            _writeCharacteristic = characteristic;
            break;
          }
        }
      }
    }
  }
}