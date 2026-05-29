import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';

class PrinterService {
  // Target broadcast name from your test receipt printout
  static const String targetDeviceName = "9printer-58B"; 

Future<void> printOrderReceipt({
    required List<Map<String, dynamic>> cart,
    required double total,
    required int waitingNumber,
    required String paymentMethod,
  }) async {
    BluetoothDevice? printerDevice;

    // 1. Scan for the 9printer
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == targetDeviceName) {
          printerDevice = r.device;
          FlutterBluePlus.stopScan();
          break;
        }
      }
    });

    await Future.delayed(const Duration(seconds: 4));
    await subscription.cancel();

    if (printerDevice == null) {
      print("Printer not found.");
      return; 
    }

    await printerDevice!.connect();
    List<BluetoothService> services = await printerDevice!.discoverServices();
    BluetoothCharacteristic? writeCharacteristic;
    
    for (BluetoothService service in services) {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.properties.writeWithoutResponse || characteristic.properties.write) {
          writeCharacteristic = characteristic;
          break;
        }
      }
    }
    
    if (writeCharacteristic != null) {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      // --- TICKET HEADER ---
      bytes += generator.text('MYJAA SWEET', styles: const PosStyles(align: PosAlign.center, bold: true, width: PosTextSize.size2, height: PosTextSize.size2));
      bytes += generator.text('Muar, Johor', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);
      
      bytes += generator.text('WAITING NO: $waitingNumber', styles: const PosStyles(align: PosAlign.center, bold: true, width: PosTextSize.size2, height: PosTextSize.size2));
      bytes += generator.feed(1);
      bytes += generator.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));

      // --- CART ITEMS ---
      for (var item in cart) {
        String itemName = item['name'];
        int qty = item['qty'];
        double price = item['price'] * qty;
        
        // Formats a clean left/right layout for 58mm
        bytes += generator.row([
          PosColumn(text: '${qty}x $itemName', width: 8, styles: const PosStyles(align: PosAlign.left)),
          PosColumn(text: price.toStringAsFixed(2), width: 4, styles: const PosStyles(align: PosAlign.right)),
        ]);
        
        // Print notes if they exist (e.g. "No Sugar")
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
      bytes += generator.feed(2);
      bytes += generator.cut();

      // Send to printer
      await writeCharacteristic.write(bytes, withoutResponse: true);
    }
  }

  Future<void> connectAndPrintTest() async {
    BluetoothDevice? printerDevice;

    // 1. Start scanning for BLE devices
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

    // 2. Listen to the scan results to find your printer
    var subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == targetDeviceName) {
          printerDevice = r.device;
          FlutterBluePlus.stopScan(); 
          break;
        }
      }
    });

    // Wait for the 4-second scan to finish
    await Future.delayed(const Duration(seconds: 4));
    await subscription.cancel();

    if (printerDevice == null) {
      print("Printer '$targetDeviceName' not found. Make sure it's turned on.");
      return;
    }

    print("Found printer! Connecting...");
    await printerDevice!.connect();
    
    // 3. Discover services to find the data pipe
    List<BluetoothService> services = await printerDevice!.discoverServices();
    BluetoothCharacteristic? writeCharacteristic;
    
    for (BluetoothService service in services) {
      for (BluetoothCharacteristic characteristic in service.characteristics) {
        if (characteristic.properties.writeWithoutResponse || characteristic.properties.write) {
          writeCharacteristic = characteristic;
          break;
        }
      }
    }
    
    if (writeCharacteristic != null) {
      // 4. Build the ESC/POS receipt data (58mm width format)
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      
      List<int> bytes = [];
      bytes += generator.text(
        'MYJAA SWEET', 
        styles: const PosStyles(
          align: PosAlign.center, 
          height: PosTextSize.size2, 
          width: PosTextSize.size2
        )
      );
      bytes += generator.text('Receipt Test Success!', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(2);
      bytes += generator.cut();

      // 5. Write binary commands directly to the hardware
      await writeCharacteristic.write(bytes, withoutResponse: true);
      print("Print data sent successfully!");
    } else {
      print("Could not locate a writable characteristic channel.");
    }
  }
}