import 'package:flutter/material.dart';

abstract final class AppColors {
  // Structure and text (60/30/10 palette)
  static const navy = Color(0xFF1E293B);
  static const surface = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);
  static const textMuted = Color(0xFF64748B);

  // Accent: active states and focus only
  static const accent = Color(0xFF0284C7);

  // Status chips: crimson text on light pink
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFDE8EC);

  // Sidebar
  static const sidebarHover = Color(0xFF334155);
  static const sidebarLine = Color(0xFF334155);
  static const sidebarText = Color(0xFFCBD5E1);
  static const sidebarMuted = Color(0xFF94A3B8);
}