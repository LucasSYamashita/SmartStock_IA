import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controla o modo de tema do app (system/light/dark)
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);
