import 'package:flutter/material.dart';

// Observateur global — enregistré dans MaterialApp.navigatorObservers.
// Permet à n'importe quel écran d'être notifié quand il redevient visible
// (ex : après qu'une route modale a été dépilée par Navigator.pop).
final RouteObserver<ModalRoute<void>> observateurRoute =
    RouteObserver<ModalRoute<void>>();
