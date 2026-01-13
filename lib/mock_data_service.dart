import 'roughness_reading.dart';

class MockDataService {
  static Future<List<String>> getOpenSRFs() async {
    await Future.delayed(const Duration(seconds: 1)); // Simulate latency
    return ['SRF-101', 'SRF-102', 'SRF-103'];
  }

  static Future<void> saveReading(
    String srfId,
    RoughnessReading data,
    String imagePath,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500)); // Simulate save
    print('--- DATA SAVED ---');
    print('SRF ID: $srfId');
    print('Ra: ${data.ra}, Rmax: ${data.rmax}, Rz: ${data.rz}');
    print('Image Path: $imagePath');
    print('------------------');
  }
}
