import 'package:flutter/material.dart';

import '../../core/session/session_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import 'reports_models.dart';

/// The short "what to do first" list on a new shop's dashboard: add a product, receive stock,
/// sell, fill in the shop's details, add the team. Each step that is not done is a button that
/// goes where it is done. It disappears for good once everything is done or the person hides it.
class OnboardingCard extends StatefulWidget {
  const OnboardingCard({
    super.key,
    required this.session,
    required this.onboarding,
    required this.onGo,
  });

  final SessionController session;
  final Onboarding onboarding;
  final ValueChanged<AppPage> onGo;

  @override
  State<OnboardingCard> createState() => _OnboardingCardState();
}

class _OnboardingCardState extends State<OnboardingCard> {
  String get _hiddenKey =>
      'onboarding.hidden.${widget.session.membership?.businessId}';

  late bool _hidden = widget.session.preferences.getBool(_hiddenKey) ?? false;

  List<(String, String, bool, AppPage)> _steps() {
    final l = strings(context);
    final o = widget.onboarding;
    final session = widget.session;
    return [
      ('products', l.onboardProducts, o.hasProducts, AppPage.products),
      ('stock', l.onboardStock, o.hasStock, AppPage.inventory),
      ('sale', l.onboardSale, o.hasSales, AppPage.sales),
      if (session.can('business.manage'))
        ('details', l.onboardDetails, o.hasDetails, AppPage.administration),
      if (session.can('staff.manage'))
        ('team', l.onboardTeam, o.hasTeam, AppPage.administration),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final l = strings(context);
    final steps = _steps();
    final done = steps.where((s) => s.$3).length;
    if (done == steps.length) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SurfaceCard(
        key: const ValueKey('onboarding-card'),
        featured: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.onboardTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ),
                Text(
                  l.onboardProgress('$done', '${steps.length}'),
                  key: const ValueKey('onboarding-progress'),
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: done / steps.length,
                minHeight: 6,
                backgroundColor: AppColors.surfaceMuted,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(height: 8),
            for (final (key, label, finished, page) in steps)
              InkWell(
                key: ValueKey('onboarding-$key'),
                borderRadius: BorderRadius.circular(10),
                onTap: finished ? null : () => widget.onGo(page),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 52),
                  child: Row(
                    children: [
                      AppIcon(
                        finished ? AppIcons.checkCircle : AppIcons.addCircle,
                        size: 22,
                        color: finished ? AppColors.success : AppColors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: finished ? AppColors.muted : AppColors.ink,
                            decoration: finished
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (!finished)
                        AppIcon(
                          AppIcons.chevron,
                          size: 18,
                          color: AppColors.muted,
                        ),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('onboarding-hide'),
                onPressed: () {
                  widget.session.preferences.setBool(_hiddenKey, true);
                  setState(() => _hidden = true);
                },
                child: Text(l.onboardHide),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
