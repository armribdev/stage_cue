part of '../sampler_screen.dart';

class _UndoPadIntent extends Intent {
  const _UndoPadIntent();
}

class _AddPadIntent extends Intent {
  const _AddPadIntent();
}

class _QuickSearchIntent extends Intent {
  const _QuickSearchIntent();
}

class _StopAllIntent extends Intent {
  const _StopAllIntent();
}

/// Recherche-éclair pré-filtrée par type de son (Ctrl+G/H/J).
class _QuickSearchFilteredIntent extends Intent {
  final SoundType type;
  const _QuickSearchFilteredIntent(this.type);
}
