import 'package:flutter/services.dart'; // Needed to load the image file
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img; // The new image package

class PrinterService {
  static const String targetDeviceName = "9printer-58B"; 

  static BluetoothDevice? _connectedDevice;
  static BluetoothCharacteristic? _writeCharacteristic;

  Future<void> printOrderReceipt({
    required List<Map<String, dynamic>> cart,
    required double total,
    required int waitingNumber,
    required String paymentMethod,
  }) async {
    
    if (_writeCharacteristic == null || _connectedDevice == null || _connectedDevice!.isConnected == false) {
      await _scanAndConnect();
    }

    if (_writeCharacteristic == null) {
      print("Printer not found or user canceled connection.");
      return; 
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile);
      List<int> bytes = [];

      String currentDate = DateFormat('dd MMM yyyy, h:mm a').format(DateTime.now());

      // --- 1. PRINT THE LOGO ---
      try {
        final ByteData data = await rootBundle.load('assets/pos.jpeg');
        final Uint8List bytesImg = data.buffer.asUint8List();
        final img.Image? logo = img.decodeImage(bytesImg);
        
        if (logo != null) {
          // Resize width to 250 pixels so it fits nicely on a 58mm roll
          final img.Image resizedLogo = img.copyResize(logo, width: 250); 
          bytes += generator.image(resizedLogo, align: PosAlign.center);
        }
      } catch (e) {
        print("Logo failed to load/print: $e");
      }

      // --- 2. TICKET HEADER ---
      bytes += generator.text('H&S CHOICES', styles: const PosStyles(align: PosAlign.center, bold: true, width: PosTextSize.size2, height: PosTextSize.size2));
      
      bytes += generator.text('LAMAN KAK MISAI, 224,', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('Kampung Parit Keroma Darat,', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('84000 Muar, Johor', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);
      
      bytes += generator.text('Sofia: +60 17-648 5374', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(1);
      
      bytes += generator.text('Date: $currentDate', styles: const PosStyles(align: PosAlign.center));
            bytes += generator.feed(1);
      bytes += generator.text('Order No: $waitingNumber', styles: const PosStyles(align: PosAlign.center, bold: true, width: PosTextSize.size2, height: PosTextSize.size2));
      bytes += generator.feed(1);
      bytes += generator.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));

      // --- 3. CART ITEMS ---
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

      // --- 4. FOOTER ---
      bytes += generator.text('--------------------------------', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.row([
        PosColumn(text: 'TOTAL:', width: 6, styles: const PosStyles(align: PosAlign.left, bold: true)),
        PosColumn(text: 'RM ${total.toStringAsFixed(2)}', width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
      bytes += generator.text('PAID VIA: ${paymentMethod.toUpperCase()}', styles: const PosStyles(align: PosAlign.left));
      
      bytes += generator.feed(2);
      bytes += generator.cut();

      await _writeCharacteristic!.write(bytes, withoutResponse: true);
      print("Print successful!");

    } catch (e) {
      print("Printer disconnected or error: $e");
      _connectedDevice = null;
      _writeCharacteristic = null;
    }
  }

  Future<void> _scanAndConnect() async {
    print("Starting new scan...");
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