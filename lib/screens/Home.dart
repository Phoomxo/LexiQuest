import 'package:flutter/material.dart';
import '../services/background_service.dart';
import 'ChooseModeScreen.dart'; // อย่าลืมนำเข้าหน้า ChooseModeScreen

class Home extends StatelessWidget {
  final BackgroundService _backgroundService = BackgroundService();

  Home({super.key});

  @override
  Widget build(BuildContext context) {
    final backgroundUrl = _backgroundService.currentBackground.backgroundUrl;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'แบบฝึกหัด',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Container(
        decoration: backgroundUrl != null
            ? BoxDecoration(
                image: DecorationImage(
                  image: NetworkImage(backgroundUrl),
                  fit: BoxFit.cover,
                ),
              )
            : null,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChooseModeScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'เรียนรู้คำศัพท์',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
