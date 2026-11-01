// Shared building blocks styled after the iOS app's lists and controls.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';

/// A page with an iOS-style large title, round buttons in the top corners,
/// and room at the bottom for the floating tab bar.
class BaselitPage extends StatelessWidget {
  const BaselitPage({
    super.key,
    required this.title,
    this.children = const [],
    this.actions = const [],
    this.largeTitle = true,
    this.header,
    this.leading = const [],
    this.background,
    this.fill,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final bool largeTitle;
  final Widget? header;

  /// Buttons on the left of the toolbar, for top-level pages.
  final List<Widget> leading;

  /// Overrides the grouped gray background, e.g. the Search tab's plain white.
  final Color? background;

  /// Fills the space under the title and header instead of a scrolling list.
  final Widget? fill;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final titleBlock = [
      if (largeTitle)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(title, style: TextStyles.largeTitle(context)),
        ),
      ?header,
    ];
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Sizes.pagePadding,
                8,
                Sizes.pagePadding,
                0,
              ),
              child: SizedBox(
                height: Sizes.roundButton,
                child: Row(
                  children: [
                    if (canPop)
                      RoundButton(
                        icon: CupertinoIcons.chevron_left,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    for (final button in leading) ...[
                      button,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: largeTitle
                          ? const SizedBox()
                          : Text(
                              title,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyles.navTitle(context),
                            ),
                    ),
                    for (final action in actions) ...[
                      const SizedBox(width: 8),
                      action,
                    ],
                    if (canPop && actions.isEmpty)
                      const SizedBox(width: Sizes.roundButton),
                  ],
                ),
              ),
            ),
            if (fill != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Sizes.pagePadding,
                  8,
                  Sizes.pagePadding,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: titleBlock,
                ),
              ),
              Expanded(child: fill!),
            ] else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    Sizes.pagePadding,
                    8,
                    Sizes.pagePadding,
                    120,
                  ),
                  children: [...titleBlock, ...children],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The white circle button with a soft shadow used in the iOS toolbar.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.label,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? label;

  /// Fill color; defaults to the iOS glass color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final child = label == null
        ? Icon(icon, size: 22, color: colors.label)
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(label!, style: TextStyles.body(context)),
          );
    return Tooltip(
      message: label ?? '',
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        elevation: 0,
        shadowColor: Colors.black,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minWidth: Sizes.roundButton),
            height: Sizes.roundButton,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color ?? colors.glass,
              borderRadius: BorderRadius.circular(Sizes.roundButton),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A gray heading above a card, like an iOS list section header.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
    child: Text(text, style: TextStyles.sectionHeader(context)),
  );
}

/// A white rounded card holding rows separated by thin indented lines.
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.children,
    this.separatorIndent = 16,
  });

  final List<Widget> children;
  final double separatorIndent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.card),
        child: ColoredBox(
          color: colors.card,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: EdgeInsets.only(left: separatorIndent, right: 16),
                    child: Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: colors.separator,
                    ),
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A list row: optional leading tile or icon, title, subtitle, and a chevron when tappable.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.bold = false,
    this.muted = false,
  });

  final String title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool bold;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = destructive
        ? colors.destructive
        : muted
        ? colors.secondaryLabel
        : colors.label;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style:
                          (bold
                                  ? TextStyles.headline(context)
                                  : TextStyles.body(context))
                              .copyWith(color: color),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      subtitle!,
                    ],
                  ],
                ),
              ),
              ?trailing,
              if (onTap != null && trailing == null && !destructive)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: colors.tertiaryLabel,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A leading icon sized like an SF Symbol in an iOS list row.
class RowIcon extends StatelessWidget {
  const RowIcon(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    child: Icon(icon, size: 22, color: color ?? context.colors.label),
  );
}

/// A label and value on one row, like SwiftUI's LabeledContent.
class ValueRow extends StatelessWidget {
  const ValueRow(this.label, this.value, {super.key, this.monospaced = false});
  final String label;
  final String value;
  final bool monospaced;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 52),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyles.body(context)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyles.body(context).copyWith(
                color: context.colors.secondaryLabel,
                fontFamily: monospaced ? 'Menlo' : null,
                fontFamilyFallback: monospaced
                    ? const ['DejaVu Sans Mono', 'Roboto Mono', 'monospace']
                    : null,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A small icon and gray text, used for counts under a row title.
class CountLabel extends StatelessWidget {
  const CountLabel(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: context.colors.secondaryLabel),
      const SizedBox(width: 6),
      Text(text, style: TextStyles.subheadline(context)),
    ],
  );
}

String plural(int count, String word) =>
    '$count ${count == 1 ? word : '${word}s'}';

/// A rounded gray square holding an icon, or the first photo when there is one.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.photo,
    this.store,
    this.size = Sizes.tile,
  });

  final IconData icon;
  final Photo? photo;
  final InventoryStore? store;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(
      size > 40 ? Radii.tile : Radii.smallTile,
    );
    if (photo != null && store != null) {
      final file = store!.photoFile(photo!);
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(
          file,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, _, _) => _placeholder(colors, radius),
        ),
      );
    }
    return _placeholder(colors, radius);
  }

  Widget _placeholder(BaselitColors colors, BorderRadius radius) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: colors.fill, borderRadius: radius),
    child: Icon(icon, size: size * 0.5, color: colors.secondaryLabel),
  );
}

/// "House › Location › Container", last part darker, like the iOS BreadcrumbView.
class Breadcrumb extends StatelessWidget {
  const Breadcrumb(this.parts, {super.key});
  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0)
            Icon(
              CupertinoIcons.chevron_right,
              size: 10,
              color: colors.secondaryLabel,
            ),
          Text(
            parts[i],
            style: TextStyles.caption(context).copyWith(
              color: i == parts.length - 1
                  ? colors.label
                  : colors.secondaryLabel,
            ),
          ),
        ],
      ],
    );
  }
}

/// Centered icon, title, and message for empty lists.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 120),
    child: Column(
      children: [
        Icon(icon, size: 56, color: context.colors.secondaryLabel),
        const SizedBox(height: 16),
        Text(title, style: TextStyles.title(context).copyWith(fontSize: 22)),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyles.subheadline(context),
        ),
      ],
    ),
  );
}

/// Rows of photo thumbnails for a detail screen.
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.store, required this.photos});
  final InventoryStore store;
  final List<Photo> photos;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      itemCount: photos.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: InteractiveViewer(
              child: Image.file(store.photoFile(photos[i])),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.tile),
          child: Image.file(
            store.photoFile(photos[i]),
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            cacheWidth: 216,
            errorBuilder: (_, _, _) =>
                IconTile(icon: CupertinoIcons.photo, size: 72),
          ),
        ),
      ),
    ),
  );
}

/// A text field inside a card row, for forms.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    required this.controller,
    required this.hint,
    this.multiline = false,
    this.number = false,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool multiline;
  final bool number;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 8 : 1,
      keyboardType: number ? TextInputType.number : null,
      textCapitalization: TextCapitalization.sentences,
      style: TextStyles.body(context),
      cursorColor: context.colors.label,
      decoration: InputDecoration(
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
  );
}
