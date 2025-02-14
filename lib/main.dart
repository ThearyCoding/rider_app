import 'package:flutter/material.dart';
import 'rider_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: RiderApp(riderId: 'rider123'),
    );
  }
}

