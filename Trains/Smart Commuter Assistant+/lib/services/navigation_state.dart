import 'package:flutter/foundation.dart';

class NavigationState {
  NavigationState._();

  static final NavigationState instance = NavigationState._();

  final ValueNotifier<int> selectedIndex = ValueNotifier<int>(0);

  void goTo(int index) {
    selectedIndex.value = index;
  }
}
