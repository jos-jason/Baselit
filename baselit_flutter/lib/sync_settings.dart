// Settings screen for signing in to a PocketBase server and watching sync.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'sync.dart';
import 'theme.dart';
import 'widgets.dart';

/// One line describing where sync stands, for the Settings row.
String syncStatus(SyncService sync) {
  if (!sync.signedIn) return 'Off';
  if (sync.syncing) return 'Syncing…';
  if (sync.lastError != null) return sync.lastError!;
  final last = sync.lastSynced;
  if (last == null) return 'Signed in as ${sync.email}';
  final time = TimeOfDay.fromDateTime(last);
  final today = DateUtils.isSameDay(last, DateTime.now());
  return 'Last synced ${today ? 'today' : '${last.month}/${last.day}'} at '
      '${time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod}:'
      '${time.minute.toString().padLeft(2, '0')} ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
}

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _url = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sync = SyncScope.of(context);
    if (_url.text.isEmpty) _url.text = sync.serverURL ?? '';
    if (_email.text.isEmpty) _email.text = sync.email ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn(SyncService sync) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bothHaveData = await sync.signIn(
        _url.text,
        _email.text,
        _password.text,
      );
      _password.clear();
      var choice = FirstSync.merge;
      if (bothHaveData && mounted) {
        choice = await _askFirstSync() ?? FirstSync.useServer;
      }
      await sync.firstSync(choice);
    } catch (error) {
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<FirstSync?> _askFirstSync() => showDialog<FirstSync>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(
        'Server Already Has Data',
        style: TextStyles.headline(context),
      ),
      content: const Text(
        'Use the server\'s inventory replaces everything on this device with what\'s '
        'on the server. Merge keeps both, which can make duplicates if this device '
        'was set up from a backup of the same inventory.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, FirstSync.merge),
          child: const Text('Merge'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, FirstSync.useServer),
          child: const Text('Use Server\'s'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sync = SyncScope.of(context);
    final colors = context.colors;
    return BaselitPage(
      title: 'Sync',
      largeTitle: false,
      children: [
        if (!sync.signedIn) ...[
          const SectionHeader('PocketBase Server'),
          GroupCard(
            children: [
              FieldRow(
                controller: _url,
                hint: 'https://pb.example.com',
                keyboardType: TextInputType.url,
              ),
              FieldRow(
                controller: _email,
                hint: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              FieldRow(controller: _password, hint: 'Password', obscure: true),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Sign in with a user from your server\'s users collection. Every Baselit '
              'app signed in to the same user keeps the same inventory, photos included.',
              style: TextStyles.caption(context),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () => _signIn(sync),
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('Sign In'),
          ),
        ] else ...[
          const SectionHeader('Server'),
          GroupCard(
            children: [
              ValueRow('Address', sync.serverURL ?? ''),
              ValueRow('Signed In As', sync.email ?? ''),
              ListRow(
                title: syncStatus(sync),
                leading: sync.syncing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : RowIcon(
                        sync.lastError != null
                            ? CupertinoIcons.exclamationmark_triangle
                            : CupertinoIcons.checkmark_circle,
                      ),
                trailing: const SizedBox(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GroupCard(
            separatorIndent: 58,
            children: [
              ListRow(
                title: 'Sync Now',
                leading: const RowIcon(CupertinoIcons.arrow_2_circlepath),
                trailing: const SizedBox(),
                onTap: sync.syncing ? null : sync.sync,
              ),
              ListRow(
                title: 'Sign Out',
                destructive: true,
                leading: RowIcon(
                  CupertinoIcons.square_arrow_left,
                  color: colors.destructive,
                ),
                trailing: const SizedBox(),
                onTap: sync.signOut,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Changes sync a few seconds after you make them, every minute while '
              'Baselit is open, and when you come back to it. Signing out keeps '
              'everything on this device.',
              style: TextStyles.caption(context),
            ),
          ),
        ],
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyles.body(context)
                  .copyWith(color: colors.destructive),
            ),
          ),
      ],
    );
  }
}
