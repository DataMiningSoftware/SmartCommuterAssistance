import 'package:flutter/material.dart';

class TransitLineStyle {
  static Color colorForLine(String line) {
    switch (line) {
      case 'MRT Kajang':
        return const Color(0xFF009A44);
      case 'LRT Kelana Jaya':
        return const Color(0xFF0A57D5);
      case 'LRT Ampang/Sri Petaling':
        return const Color(0xFF8C4A2F);
      case 'KTM Seremban':
        return const Color(0xFF1F3C98);
      case 'Interchange':
        return const Color(0xFF667085);
      default:
        return const Color(0xFF667085);
    }
  }
}
