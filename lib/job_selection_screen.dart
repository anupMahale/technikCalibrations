import 'package:flutter/material.dart';
import 'mock_data_service.dart';
import 'camera_screen.dart';

class JobSelectionScreen extends StatelessWidget {
  const JobSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Job (SRF)')),
      body: FutureBuilder<List<String>>(
        future: MockDataService.getOpenSRFs(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No open SRFs found.'));
          }

          final srfList = snapshot.data!;
          return ListView.builder(
            itemCount: srfList.length,
            itemBuilder: (context, index) {
              final srf = srfList[index];
              return ListTile(
                title: Text(srf),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CameraScreen(srfId: srf),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
