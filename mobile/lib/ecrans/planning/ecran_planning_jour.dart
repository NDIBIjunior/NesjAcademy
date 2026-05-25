import 'package:flutter/material.dart';

// Planning du jour — liste des sessions à faire aujourd'hui — à implémenter
class EcranPlanningJour extends StatelessWidget {
  const EcranPlanningJour({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon planning du jour')),
      body: const Center(child: Text('Sessions du jour — à venir')),
    );
  }
}