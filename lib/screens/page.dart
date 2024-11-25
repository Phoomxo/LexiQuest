import 'package:flutter/material.dart';

class NewPage extends StatelessWidget {
  final String name; // รับค่า name จากหน้า Main

  const NewPage({Key? key, required this.name}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('New Page'),
      ),
      body: Center(
        child: Text(
          'Hello, $name!',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
