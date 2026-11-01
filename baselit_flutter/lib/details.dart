// Detail screens for houses, locations, containers, and items.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'bubble_grid.dart';
import 'forms.dart';
import 'models.dart';
import 'store.dart';
import 'tabs.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shared "Locations / Containers / Items" sections for places and containers.
List<Widget> _contents(
  BuildContext context,
  InventoryStore store, {
  List<Location> locations = const [],
  List<StorageContainer> containers = const [],
  List<Item> items = const [],
}) => [
  if (locations.isNotEmpty) ...[
    const SectionHeader('Locations'),
    GroupCard(
      separatorIndent: 74,
      children: [
        for (final l in locations)
          ListRow(
            title: l.name,
            leading: const IconTile(icon: CupertinoIcons.map_pin),
            subtitle: CountLabel(
              CupertinoIcons.cube_box,
              plural(store.itemsInLocation(l).length, 'item'),
            ),
            onTap: () => push(context, LocationDetailScreen(location: l)),
          ),
      ],
    ),
  ],
  if (containers.isNotEmpty) ...[
    const SectionHeader('Containers'),
    GroupCard(
      separatorIndent: 74,
      children: [for (final c in containers) containerRow(context, store, c)],
    ),
  ],
  if (items.isNotEmpty) ...[
    const SectionHeader('Items'),
    GroupCard(
      separatorIndent: 74,
      children: [for (final i in items) itemRow(context, store, i)],
    ),
  ],
  if (locations.isEmpty && containers.isEmpty && items.isEmpty)
    const EmptyState(
      icon: CupertinoIcons.tray,
      title: 'Empty',
      message: 'Nothing is stored here yet.',
    ),
];

/// The "View All Items & Containers" row that opens a full-screen bubble grid.
Widget _viewAllRow(
  BuildContext context,
  String title,
  List<Item> items,
  List<StorageContainer> containers,
) {
  if (items.isEmpty && containers.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 22),
    child: GroupCard(
      separatorIndent: 58,
      children: [
        ListRow(
          title: 'View All Items & Containers',
          leading: const RowIcon(CupertinoIcons.circle_grid_hex),
          trailing: const SizedBox(),
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => BubbleGridScreen(
                title: title,
                items: items,
                containers: containers,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Full-screen honeycomb of everything inside a house, location, or container.
class BubbleGridScreen extends StatelessWidget {
  const BubbleGridScreen({
    super.key,
    required this.title,
    required this.items,
    required this.containers,
  });

  final String title;
  final List<Item> items;
  final List<StorageContainer> containers;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    // Leave out anything deleted while this screen is open
    final liveItems = items.where(store.items.contains);
    final liveContainers = containers.where(store.containers.contains);
    return BaselitPage(
      title: title,
      largeTitle: false,
      background: context.colors.plainBackground,
      showBack: false,
      leading: [
        RoundButton(
          icon: CupertinoIcons.xmark,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      actions: const [SizedBox(width: Sizes.roundButton)],
      fill: SafeArea(
        top: false,
        child: BubbleGrid(
          store: store,
          entries: bubbleEntries(
            store,
            items: liveItems,
            containers: liveContainers,
            openItem: (item) => push(context, ItemDetailScreen(item: item)),
            openContainer: (c) =>
                push(context, ContainerDetailScreen(container: c)),
          ),
        ),
      ),
    );
  }
}

Widget _notes(BuildContext context, String? notes) =>
    (notes == null || notes.isEmpty)
    ? const SizedBox.shrink()
    : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader('Notes'),
          GroupCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(notes, style: TextStyles.body(context)),
                ),
              ),
            ],
          ),
        ],
      );

class UnassignedScreen extends StatelessWidget {
  const UnassignedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return BaselitPage(
      title: 'Unassigned',
      largeTitle: false,
      children: _contents(context, store, items: store.unassignedItems),
    );
  }
}

class HouseDetailScreen extends StatelessWidget {
  const HouseDetailScreen({super.key, required this.house});
  final House house;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return BaselitPage(
      title: house.name,
      actions: [
        RoundButton(
          icon: CupertinoIcons.plus,
          onPressed: () async {
            final name = await askForName(
              context,
              'New Location',
              'Location name',
            );
            if (name != null) await store.addLocation(name, house);
          },
        ),
      ],
      children: [
        if (house.address?.isNotEmpty ?? false)
          GroupCard(children: [ValueRow('Address', house.address!)]),
        _notes(context, house.notes),
        _viewAllRow(
          context,
          house.name,
          store.itemsWithinHouse(house),
          store.containersWithinHouse(house),
        ),
        ..._contents(
          context,
          store,
          locations: store.topLocations(house),
          containers: store.containersInHouse(house),
          items: store.itemsInHouse(house),
        ),
      ],
    );
  }
}

class LocationDetailScreen extends StatelessWidget {
  const LocationDetailScreen({super.key, required this.location});
  final Location location;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return BaselitPage(
      title: location.name,
      header: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Breadcrumb(store.locationPath(location)),
      ),
      children: [
        _notes(context, location.notes),
        _viewAllRow(
          context,
          location.name,
          store.itemsWithinLocation(location),
          store.containersWithinLocation(location),
        ),
        ..._contents(
          context,
          store,
          locations: store.subLocations(location),
          containers: store.containersInLocation(location),
          items: store.itemsInLocation(location),
        ),
      ],
    );
  }
}

class ContainerDetailScreen extends StatelessWidget {
  const ContainerDetailScreen({super.key, required this.container});
  final StorageContainer container;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final photos = store.photosFor(containerID: container.exportID);
    return BaselitPage(
      title: container.name,
      children: [
        if (photos.isNotEmpty)
          GroupCard(
            children: [PhotoStrip(store: store, photos: photos)],
          ),
        const SizedBox(height: 12),
        GroupCard(
          children: [
            ValueRow('ID', container.identifier, monospaced: true),
            if (container.containerType?.isNotEmpty ?? false)
              ValueRow('Type', container.containerType!),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Breadcrumb(store.containerPath(container)),
              ),
            ),
          ],
        ),
        _notes(context, container.notes),
        _viewAllRow(
          context,
          container.name,
          store.itemsWithinContainer(container),
          store.containersWithinContainer(container),
        ),
        ..._contents(
          context,
          store,
          containers: store.subContainers(container),
          items: store.itemsInContainer(container),
        ),
      ],
    );
  }
}

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.item});
  final Item item;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = context.colors;
    final photos = store.photosFor(itemID: item.exportID);
    final homes = store.homesForItem(item);
    final details = [
      if (item.itemDescription?.isNotEmpty ?? false)
        ValueRow('Description', item.itemDescription!),
      if (item.quantity > 1) ValueRow('Quantity', '${item.quantity}'),
      if (item.brand?.isNotEmpty ?? false) ValueRow('Brand', item.brand!),
      if (item.model?.isNotEmpty ?? false) ValueRow('Model', item.model!),
      if (item.condition?.isNotEmpty ?? false)
        ValueRow('Condition', item.condition!),
    ];

    return BaselitPage(
      title: item.name,
      largeTitle: false,
      actions: [
        RoundButton(
          icon: CupertinoIcons.pencil,
          label: 'Edit',
          onPressed: () => push(context, ItemFormScreen(item: item)),
        ),
      ],
      children: [
        GroupCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(item.name, style: TextStyles.title(context)),
              ),
            ),
          ],
        ),
        if (photos.isNotEmpty) ...[
          const SectionHeader('Photos'),
          GroupCard(
            children: [PhotoStrip(store: store, photos: photos)],
          ),
        ],
        const SizedBox(height: 22),
        GroupCard(
          children: [
            ValueRow('ID', item.identifier, monospaced: true),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Breadcrumb(store.itemPath(item)),
              ),
            ),
          ],
        ),
        if (details.isNotEmpty) ...[
          const SectionHeader('Details'),
          GroupCard(children: details),
        ],
        _notes(context, item.notes),
        const SectionHeader('Stored In'),
        GroupCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  store.itemPath(item).join(' › '),
                  style: TextStyles.subheadline(context),
                ),
              ),
            ),
          ],
        ),
        const SectionHeader('Belongs'),
        GroupCard(
          separatorIndent: 58,
          children: [
            for (final home in homes)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Breadcrumb(store.homePath(home)),
                ),
              ),
            if (store.itemHouse(item) != null)
              store.isAtHome(item)
                  ? ListRow(
                      title: 'Current location is home',
                      muted: true,
                      leading: RowIcon(
                        CupertinoIcons.checkmark_alt_circle_fill,
                        color: colors.secondaryLabel,
                      ),
                    )
                  : ListRow(
                      title: 'Set Current Location as Home',
                      leading: const RowIcon(CupertinoIcons.house_fill),
                      trailing: const SizedBox(),
                      onTap: () => store.setCurrentSpotAsHome(item),
                    ),
            if (homes.isEmpty && store.itemHouse(item) == null)
              ListRow(title: 'Not assigned to a house yet', muted: true),
          ],
        ),
        const SizedBox(height: 22),
        GroupCard(
          separatorIndent: 58,
          children: [
            ListRow(
              title: 'Edit Item',
              leading: const RowIcon(CupertinoIcons.pencil),
              trailing: const SizedBox(),
              onTap: () => push(context, ItemFormScreen(item: item)),
            ),
            ListRow(
              title: 'Delete Item',
              destructive: true,
              leading: const RowIcon(CupertinoIcons.trash),
              onTap: () async {
                if (await confirmDelete(context, item.name)) {
                  await store.deleteItem(item);
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
