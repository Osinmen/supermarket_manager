import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Row(
        mainAxisAlignment: .start,
        children: [_SideBar()]),
    );
  }
}

class _SideBar extends StatelessWidget {
  const _SideBar({super.key});
  @override
  Widget build(BuildContext context) {
    final List routes = ['DashBoard', 'Report', 'Inventory', 'Price List'];
    return Container(
      height: double.infinity,
      color: Colors.redAccent,
      child: ListView.builder(
        itemCount: routes.length,
        itemBuilder: (context, index) {
          
          return Container(
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
            ),
            
          );
        },
      ),
    );
  }
}
