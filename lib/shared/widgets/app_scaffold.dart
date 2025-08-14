import 'package:flutter/material.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottom;
  const AppScaffold(
      {super.key,
      required this.title,
      required this.body,
      this.actions,
      this.bottom});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: bottom,
    );
  }
}
