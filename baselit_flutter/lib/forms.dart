// Item form, small dialogs, and the Settings screen with backup import and export.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

Future<String?> askForName(
  BuildContext context,
  String title,
  String hint,
) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: TextStyles.headline(context)),
      content: Container(
        decoration: BoxDecoration(
          color: context.colors.fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: FieldRow(controller: controller, hint: hint, autofocus: true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  return (name == null || name.isEmpty) ? null : name;
}

Future<bool> confirmDelete(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name?', style: TextStyles.headline(context)),
        content: const Text('This will permanently delete this item.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.colors.destructive),
            ),
          ),
        ],
      ),
    ) ??
    false;

/// Adds or edits an item. Places are chosen from one list of every house,
/// location, and container, shown by their full path.
class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({super.key, this.item});
  final Item? item;

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  late final _name = TextEditingController(text: widget.item?.name);
  late final _description = TextEditingController(
    text: widget.item?.itemDescription,
  );
  late final _quantity = TextEditingController(
    text: '${widget.item?.quantity ?? 1}',
  );
  late final _brand = TextEditingController(text: widget.item?.brand);
  late final _model = TextEditingController(text: widget.item?.model);
  late final _condition = TextEditingController(text: widget.item?.condition);
  late final _notes = TextEditingController(text: widget.item?.notes);
  late String _place = _placeKey(widget.item);

  static String _placeKey(Item? item) {
    if (item?.containerID != null) return 'c:${item!.containerID}';
    if (item?.locationID != null) return 'l:${item!.locationID}';
    if (item?.houseID != null) return 'h:${item!.houseID}';
    return '';
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save(InventoryStore store) async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final item = widget.item ?? Item(name: name);
    item
      ..name = name
      ..itemDescription = _text(_description)
      ..quantity = int.tryParse(_quantity.text) ?? 1
      ..brand = _text(_brand)
      ..model = _text(_model)
      ..condition = _text(_condition)
      ..notes = _text(_notes)
      ..houseID = _place.startsWith('h:') ? _place.substring(2) : null
      ..locationID = _place.startsWith('l:') ? _place.substring(2) : null
      ..containerID = _place.startsWith('c:') ? _place.substring(2) : null;
    await store.saveItem(item);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addPhoto(InventoryStore store) async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Images',
          extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
        ),
      ],
    );
    if (file != null) {
      await store.addPhoto(File(file.path), itemID: widget.item!.exportID);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final colors = context.colors;
    final places = <String, String>{
      '': 'Unassigned',
      for (final h in store.sortedHouses) 'h:${h.exportID}': h.name,
      for (final l in store.locations)
        'l:${l.exportID}': store.locationPath(l).join(' › '),
      for (final c in store.containers)
        'c:${c.exportID}': store.containerPath(c).join(' › '),
    };
    if (!places.containsKey(_place)) _place = '';
    final sortedPlaces = places.entries.toList()
      ..sort(
        (a, b) => a.key.isEmpty
            ? -1
            : b.key.isEmpty
            ? 1
            : a.value.compareTo(b.value),
      );

    return BaselitPage(
      title: widget.item == null ? 'New Item' : 'Edit Item',
      largeTitle: false,
      actions: [
        RoundButton(
          icon: CupertinoIcons.checkmark,
          label: 'Save',
          onPressed: () => _save(store),
        ),
      ],
      children: [
        GroupCard(
          children: [
            FieldRow(
              controller: _name,
              hint: 'Name',
              autofocus: widget.item == null,
            ),
          ],
        ),
        const SectionHeader('Stored In'),
        GroupCard(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _place,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(18),
                  dropdownColor: colors.card,
                  icon: Icon(
                    CupertinoIcons.chevron_up_chevron_down,
                    size: 16,
                    color: colors.secondaryLabel,
                  ),
                  style: TextStyles.body(context),
                  items: [
                    for (final p in sortedPlaces)
                      DropdownMenuItem(
                        value: p.key,
                        child: Text(p.value, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) => setState(() => _place = value ?? ''),
                ),
              ),
            ),
          ],
        ),
        const SectionHeader('Details'),
        GroupCard(
          children: [
            FieldRow(controller: _description, hint: 'Description'),
            FieldRow(controller: _quantity, hint: 'Quantity', number: true),
            FieldRow(controller: _brand, hint: 'Brand'),
            FieldRow(controller: _model, hint: 'Model'),
            FieldRow(controller: _condition, hint: 'Condition'),
          ],
        ),
        const SectionHeader('Notes'),
        GroupCard(
          children: [
            FieldRow(
              controller: _notes,
              hint: 'Keywords and notes',
              multiline: true,
            ),
          ],
        ),
        if (widget.item != null) ...[
          const SizedBox(height: 22),
          GroupCard(
            children: [
              ListRow(
                title: 'Add Photo',
                leading: const RowIcon(CupertinoIcons.photo),
                trailing: const SizedBox(),
                onTap: () => _addPhoto(store),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  void _say(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  /// Imports a backup .zip or its JSON file, or with [folder] an unzipped backup folder.
  Future<void> _import(InventoryStore store, {bool folder = false}) async {
    final path = folder
        ? await getDirectoryPath(confirmButtonText: 'Import')
        : (await openFile(
            acceptedTypeGroups: [
              const XTypeGroup(
                label: 'Baselit Backup',
                extensions: ['zip', 'json'],
                uniformTypeIdentifiers: ['public.zip-archive', 'public.json'],
              ),
            ],
          ))?.path;
    if (path == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Replace everything?', style: TextStyles.headline(context)),
        content: const Text(
          'Importing replaces all houses, items, and photos on this device with the backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      _say('Imported ${await store.importBackup(path)}.');
    } catch (error) {
      _say('Import failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(InventoryStore store) async {
    final now = DateTime.now();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final location = await getSaveLocation(
      suggestedName: 'Baselit Backup $stamp.zip',
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Zip', extensions: ['zip']),
      ],
    );
    if (location == null) return;
    setState(() => _busy = true);
    try {
      await store.exportBackup(location.path);
      _say('Backup saved.');
    } catch (error) {
      _say('Export failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return BaselitPage(
      title: 'Settings',
      largeTitle: false,
      children: [
        const SectionHeader('Backup'),
        GroupCard(
          separatorIndent: 58,
          children: [
            ListRow(
              title: 'Import Backup',
              leading: const RowIcon(CupertinoIcons.square_arrow_down),
              trailing: const SizedBox(),
              onTap: _busy ? null : () => _import(store),
            ),
            ListRow(
              title: 'Import Backup Folder',
              leading: const RowIcon(CupertinoIcons.folder),
              trailing: const SizedBox(),
              onTap: _busy ? null : () => _import(store, folder: true),
            ),
            ListRow(
              title: 'Export Backup',
              leading: const RowIcon(CupertinoIcons.square_arrow_up),
              trailing: const SizedBox(),
              onTap: _busy ? null : () => _export(store),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Backups use the same .zip format as Baselit on iPhone, so you can move your '
            'inventory between devices by exporting on one and importing on the other. '
            'If the backup was unzipped into a folder, use Import Backup Folder.',
            style: TextStyles.caption(context),
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        const SectionHeader('On This Device'),
        GroupCard(
          children: [
            ValueRow('Houses', '${store.houses.length}'),
            ValueRow('Containers', '${store.containers.length}'),
            ValueRow('Items', '${store.items.length}'),
            ValueRow('Photos', '${store.photos.length}'),
          ],
        ),
      ],
    );
  }
}
