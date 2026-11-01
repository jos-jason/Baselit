import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'store.dart';
import 'tabs.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = InventoryStore()..load();
  runApp(BaselitApp(store: store));
}

class BaselitApp extends StatelessWidget {
  const BaselitApp({super.key, required this.store, this.fontFamily});
  final InventoryStore store;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) => StoreScope(
        store: store,
        child: MaterialApp(
          title: 'Baselit',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light, fontFamily: fontFamily),
          darkTheme: buildTheme(Brightness.dark, fontFamily: fontFamily),
          home: const HomeShell(),
        ),
      );
}

class _TabInfo {
  const _TabInfo(this.label, this.icon, this.selectedIcon, this.root);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget root;
}

const _tabs = [
  _TabInfo('Search', CupertinoIcons.search, CupertinoIcons.search, SearchTab()),
  _TabInfo('Places', CupertinoIcons.house, CupertinoIcons.house_fill, PlacesTab()),
  _TabInfo('Containers', CupertinoIcons.archivebox, CupertinoIcons.archivebox_fill, ContainersTab()),
  _TabInfo('Items', CupertinoIcons.cube_box, CupertinoIcons.cube_box_fill, ItemsTab()),
];

/// Four tabs, each with its own navigation stack, under a floating pill tab bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selected = 0;
  final _navigators = List.generate(_tabs.length, (_) => GlobalKey<NavigatorState>());

  void _select(int index) {
    if (index == _selected) {
      // Tapping the current tab again returns to its first screen, like iOS.
      _navigators[index].currentState?.popUntil((route) => route.isFirst);
    }
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigators[_selected].currentState?.maybePop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            if (!store.loaded)
              const Center(child: CircularProgressIndicator())
            else
              IndexedStack(
                index: _selected,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Navigator(
                      key: _navigators[i],
                      onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _tabs[i].root),
                    ),
                ],
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Center(child: FloatingTabBar(selected: _selected, onSelect: _select)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded floating tab bar from iOS 26, with a soft pill behind the selected tab.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({super.key, required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.card.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(Radii.tabBar),
        border: Border.all(color: colors.separator.withValues(alpha: 0.25), width: 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  height: 56,
                  decoration: BoxDecoration(
                    color: i == selected ? colors.tabHighlight : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.tabBar - 4),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_tabs[i].selectedIcon,
                          size: 24, color: colors.label),
                      const SizedBox(height: 2),
                      Text(
                        _tabs[i].label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                          color: colors.label,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
