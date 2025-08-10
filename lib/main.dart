import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: ColoredBox(color: Colors.red, child: Center(child: Text('A - UI OK', style: TextStyle(color: Colors.white, fontSize: 24)))),
    ),
  ));
}