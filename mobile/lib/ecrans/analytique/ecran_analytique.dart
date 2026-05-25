import 'package:flutter/material.dart';

// Tableau de bord de progression et statistiques — à implémenter
class EcranAnalytique extends StatelessWidget {
  const EcranAnalytique({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ma progression')),
      body: const Center(child: Text('Statistiques et graphiques — à venir')),
    );
  }
}