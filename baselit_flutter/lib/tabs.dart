// The four top-level tabs: Search, Places, Containers, Items.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'bubble_grid.dart';
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
Widget containerRow(
  BuildContext context,
  InventoryStore store,
  StorageContainer container,
) {
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

/// Matches the iOS Search tab: a white page with the bubble grid while the
/// search field is empty, and the usual gray grouped list once you type.
class _SearchTabState extends State<SearchTab> {
  final _query = TextEditingController();
  String? _houseID;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _filterButton(InventoryStore store, BaselitColors colors) =>
      PopupMenuButton<String>(
        tooltip: 'Filter by house',
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        color: colors.card,
        onSelected: (id) => setState(() => _houseID = id.isEmpty ? null : id),
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: '',
            checked: _houseID == null,
            child: const Text('All Houses'),
          ),
          for (final h in store.sortedHouses)
            CheckedPopupMenuItem(
              value: h.exportID,
              checked: _houseID == h.exportID,
              child: Text(h.name),
            ),
        ],
        child: IgnorePointer(
          child: RoundButton(
            icon: _houseID == null
                ? CupertinoIcons.line_horizontal_3_decrease_circle
                : CupertinoIcons.line_horizontal_3_decrease_circle_fill,

            onPressed: () {},
          ),
        ),
      );

  Widget _searchField(BaselitColors colors) => Container(
    height: 48,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: colors.searchFill,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Row(
      children: [
        Icon(CupertinoIcons.search, size: 20, color: colors.label),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            style: TextStyles.body(context),
            cursorColor: colors.label,
            decoration: const InputDecoration(
              hintText: 'Search everything...',
              isDense: true,
            ),
          ),
        ),
        if (_query.text.isNotEmpty)
          GestureDetector(
            onTap: () => setState(_query.clear),
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 18,
              color: colors.tertiaryLabel,
            ),
          ),
      ],
    ),
  );

  /// Shown when the house filter hides everything, with a way back to all houses.
  Widget _filteredEmpty(House house) => Column(
    children: [
      EmptyState(
        icon: CupertinoIcons.line_horizontal_3_decrease_circle,
        title: 'No Results',
        message: 'Nothing in ${house.name} matches.',
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: () => setState(() => _houseID = null),
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
        child: const Text('Show All Houses'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = context.colors;
    final query = _query.text.trim();
    final house = store.house(_houseID);
    final toolbar = (
      leading: [
        RoundButton(
          icon: CupertinoIcons.gear,
          onPressed: () => push(context, const SettingsScreen()),
        ),
      ],
      actions: [_filterButton(store, colors)],
    );

    if (query.isEmpty) {
      final entries = bubbleEntries(
        store,
        items: store.items.where(
          (i) => _houseID == null || store.itemHouse(i)?.exportID == _houseID,
        ),
        containers: store.containers.where(
          (c) =>
              _houseID == null || store.containerHouse(c)?.exportID == _houseID,
        ),
        openItem: (item) => push(context, ItemDetailScreen(item: item)),
        openContainer: (c) =>
            push(context, ContainerDetailScreen(container: c)),
      );
      return BaselitPage(
        title: 'Search',
        background: colors.plainBackground,
        leading: toolbar.leading,
        actions: toolbar.actions,
        header: _searchField(colors),
        fill: entries.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 90),
                child: BubbleGrid(store: store, entries: entries),
              )
            : SingleChildScrollView(
                child: house != null
                    ? _filteredEmpty(house)
                    : const EmptyState(
                        icon: CupertinoIcons.search,
                        title: 'Search',
                        message: 'Search across houses, locations, containers, and items.',
                      ),
              ),
      );
    }

    final q = query.toLowerCase();
    bool has(String? field) => field?.toLowerCase().contains(q) ?? false;
    final houses = store.sortedHouses
        .where(
          (h) =>
              (has(h.name) || has(h.address) || has(h.notes)) &&
              (_houseID == null || h.exportID == _houseID),
        )
        .toList();
    final locations =
        store.locations
            .where(
              (l) =>
                  (has(l.name) || has(l.notes)) &&
                  (_houseID == null ||
                      store.locationHouse(l)?.exportID == _houseID),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final containers = store.searchContainers(query, houseID: _houseID);
    final items = store.searchItems(query, houseID: _houseID);
    final nothing =
        houses.isEmpty &&
        locations.isEmpty &&
        containers.isEmpty &&
        items.isEmpty;

    return BaselitPage(
      title: 'Search',
      leading: toolbar.leading,
      actions: toolbar.actions,
      header: _searchField(colors),
      children: [
        if (nothing)
          house != null
              ? _filteredEmpty(house)
              : const EmptyState(
                  icon: CupertinoIcons.search,
                  title: 'No Results',
                  message: 'Nothing matched your search.',
                ),
        if (houses.isNotEmpty) ...[
          const SectionHeader('Houses'),
          GroupCard(
            separatorIndent: 74,
            children: [
              for (final h in houses)
                ListRow(
                  title: h.name,
                  leading: const IconTile(icon: CupertinoIcons.house),
                  onTap: () => push(context, HouseDetailScreen(house: h)),
                ),
            ],
          ),
        ],
        if (locations.isNotEmpty) ...[
          const SectionHeader('Locations'),
          GroupCard(
            separatorIndent: 74,
            children: [
              for (final l in locations)
                ListRow(
                  title: l.name,
                  leading: const IconTile(icon: CupertinoIcons.map_pin),
                  subtitle: Breadcrumb(store.locationPath(l)..removeLast()),
                  onTap: () => push(context, LocationDetailScreen(location: l)),
                ),
            ],
          ),
        ],
        if (containers.isNotEmpty) ...[
          const SectionHeader('Containers'),
          GroupCard(
            separatorIndent: 74,
            children: [
              for (final c in containers) containerRow(context, store, c),
            ],
          ),
        ],
        if (items.isNotEmpty) ...[
          const SectionHeader('Items'),
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
                  subtitle: CountLabel(
                    CupertinoIcons.cube_box,
                    plural(unassigned, 'item'),
                  ),
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
            children: [
              for (final c in containers) containerRow(context, store, c),
            ],
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
