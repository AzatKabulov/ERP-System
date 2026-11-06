import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';

/// Short how-to cards for the main jobs. Plain steps in the shopkeeper's words: anyone can open
/// this from Settings (and from the first-run list) when they do not know what to press.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, this.onWriteToUs});

  /// Shown under the topics for people who may write to us.
  final VoidCallback? onWriteToUs;

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final topics = <(String, AppIconData, String, String)>[
      ('receive', AppIcons.stock, l.helpReceiveTitle, l.helpReceiveBody),
      ('sell', AppIcons.sale, l.helpSellTitle, l.helpSellBody),
      ('return', AppIcons.returnArrow, l.helpReturnTitle, l.helpReturnBody),
      ('warranty', AppIcons.shield, l.helpWarrantyTitle, l.helpWarrantyBody),
      ('stock', AppIcons.box, l.helpStockTitle, l.helpStockBody),
      ('money', AppIcons.chart, l.helpMoneyTitle, l.helpMoneyBody),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.helpTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.helpIntro,
                    style: const TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  for (final (key, icon, title, body) in topics)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SurfaceCard(
                        flat: true,
                        padding: 4,
                        child: Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: ValueKey('help-$key'),
                            leading: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                color: AppColors.tint,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: AppIcon(
                                  icon,
                                  size: 18,
                                  color: AppColors.blue,
                                ),
                              ),
                            ),
                            title: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              16,
                            ),
                            expandedAlignment: Alignment.centerLeft,
                            children: [
                              Text(body, style: const TextStyle(height: 1.5)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    l.helpMore,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (onWriteToUs != null) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: OutlinedButton.icon(
                        key: const ValueKey('help-write-us'),
                        onPressed: onWriteToUs,
                        icon: const AppIcon(AppIcons.chat, size: 18),
                        label: Text(l.supportTitle),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
