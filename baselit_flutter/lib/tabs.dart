// The four top-level tabs: Search, Places, Containers, Items.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'details.dart';
import 'forms.dart';
import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

void push(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

/// A list row for an item: photo or box tile, name, and where it's stored.
Widget itemRow(BuildContext context, InventoryStore store, Item item) {
  final photos = store.photosFor(itemID: item.exportID);
  return ListRow(
    title: item.name,
    leading: IconTile(
      icon: CupertinoIcons.cube_box,
      photo: photos.isEmpty ? null : photos.first,
      store: store,
    ),
    subtitle: Breadcrumb(store.itemPath(item)),
    onTap: () => push(context, ItemDetailScreen(item: item)),
  );
}

/// A list row for a container: photo or archive tile, name, and where it is.
Widget containerRow(BuildContext context, InventoryStore store, StorageContainer container) {
  final photos = store.photosFor(containerID: container.exportID);
  final count = store.itemsInContainer(container).length;
  return ListRow(
    title: container.name,
    leading: IconTile(
      icon: CupertinoIcons.archivebox,
      photo: photos.isEmpty ? null : photos.first,
      store: store,
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Breadcrumb(store.containerPath(container)..removeLast()),
        if (count > 0) ...[
          const SizedBox(height: 2),
          CountLabel(CupertinoIcons.cube_box, plural(count, 'item')),
        ],
      ],
    ),
    onTap: () => push(context, ContainerDetailScreen(container: container)),
  );
}

// MARK: - Search

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _query = TextEditingController();
  String? _houseID;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = context.colors;
    final query = _query.text;
    final items = store.searchItems(query, houseID: _houseID);
    final containers = store.searchContainers(query, houseID: _houseID);
    final house = store.house(_houseID);

    return BaselitPage(
      title: 'Search',
      actions: [
        PopupMenuButton<String?>(
          tooltip: 'Filter by house',
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          color: colors.card,
          onSelected: (id) => setState(() => _houseID = id == '' ? null : id),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(value: '', checked: _houseID == null, child: const Text('All Houses')),
            for (final h in store.sortedHouses)
              CheckedPopupMenuItem(value: h.exportID, checked: _houseID == h.exportID, child: Text(h.name)),
          ],
          child: IgnorePointer(
            child: RoundButton(
              icon: _houseID == null
                  ? CupertinoIcons.line_horizontal_3_decrease_circle
                  : CupertinoIcons.line_horizontal_3_decrease_circle_fill,
              onPressed: () {},
            ),
          ),
        ),
        RoundButton(icon: CupertinoIcons.gear, onPressed: () => push(context, const SettingsScreen())),
      ],
      header: Column(
        children: [
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: colors.fill, borderRadius: BorderRadius.circular(22)),
            child: Row(
              children: [
                Icon(CupertinoIcons.search, size: 18, color: colors.secondaryLabel),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    style: TextStyles.body(context),
                    cursorColor: colors.label,
                    decoration: const InputDecoration(hintText: 'Items, notes, brands…', isDense: true),
                  ),
                ),
                if (query.isNotEmpty)
                  GestureDetector(
                    onTap: () => setState(_query.clear),
                    child: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: colors.tertiaryLabel),
                  ),
              ],
            ),
          ),
          if (house != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: Icon(CupertinoIcons.house_fill, size: 14, color: colors.label),
                  label: Text(house.name),
                  onDeleted: () => setState(() => _houseID = null),
                  shape: const StadiumBorder(),
                  side: BorderSide.none,
                  backgroundColor: colors.card,
                ),
              ),
            ),
        ],
      ),
      children: [
        if (items.isEmpty && containers.isEmpty)
          EmptyState(
            icon: CupertinoIcons.search,
            title: 'No Results',
            message: house == null
                ? 'Nothing matches “$query”.'
                : 'Nothing in ${house.name} matches. Try All Houses.',
          ),
        if (containers.isNotEmpty) ...[
          const SectionHeader('Containers'),
          GroupCard(
            separatorIndent: 74,
            children: [for (final c in containers) containerRow(context, store, c)],
          ),
        ],
        if (items.isNotEmpty) ...[
          SectionHeader(query.isEmpty ? 'All Items' : 'Items'),
          GroupCard(
            separatorIndent: 74,
            children: [for (final i in items) itemRow(context, store, i)],
          ),
        ],
      ],
    );
  }
}

// MARK: - Places

class PlacesTab extends StatelessWidget {
  const PlacesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final unassigned = store.unassignedItems.length;
    return BaselitPage(
      title: 'Places',
      actions: [
        RoundButton(
          icon: CupertinoIcons.plus,
          onPressed: () async {
            final name = await askForName(context, 'New House', 'House name');
            if (name != null) await store.addHouse(name);
          },
        ),
      ],
      children: [
        if (store.houses.isEmpty && unassigned == 0)
          const EmptyState(
            icon: CupertinoIcons.house,
            title: 'No Places',
            message: 'Add a house, or import a backup from Settings on the Search tab.',
          )
        else
          GroupCard(
            separatorIndent: 74,
            children: [
              if (unassigned > 0)
                ListRow(
                  title: 'Unassigned',
                  bold: true,
                  leading: const IconTile(icon: CupertinoIcons.question_square),
                  subtitle: CountLabel(CupertinoIcons.cube_box, plural(unassigned, 'item')),
                  onTap: () => push(context, const UnassignedScreen()),
                ),
              for (final house in store.sortedHouses)
                ListRow(
                  title: house.name,
                  bold: true,
                  leading: const IconTile(icon: CupertinoIcons.house),
                  subtitle: CountLabel(
                    CupertinoIcons.map_pin,
                    plural(store.topLocations(house).length, 'location'),
                  ),
                  onTap: () => push(context, HouseDetailScreen(house: house)),
                ),
            ],
          ),
      ],
    );
  }
}

// MARK: - Containers

class ContainersTab extends StatelessWidget {
  const ContainersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final containers = store.sortedContainers;
    return BaselitPage(
      title: 'Containers',
      children: [
        if (containers.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.archivebox,
            title: 'No Containers',
            message: 'Containers you add on iPhone appear here after you import a backup.',
          )
        else
          GroupCard(
            separatorIndent: 74,
            children: [for (final c in containers) containerRow(context, store, c)],
          ),
      ],
    );
  }
}

// MARK: - Items

class ItemsTab extends StatelessWidget {
  const ItemsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final items = store.sortedItems;
    return BaselitPage(
      title: 'Items',
      actions: [
        RoundButton(
          icon: CupertinoIcons.plus,
          onPressed: () => push(context, const ItemFormScreen()),
        ),
      ],
      children: [
        if (items.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.cube_box,
            title: 'No Items',
            message: 'Add an item, or import a backup from Settings on the Search tab.',
          )
        else
          GroupCard(
            separatorIndent: 74,
            children: [for (final i in items) itemRow(context, store, i)],
          ),
      ],
    );
  }
}
