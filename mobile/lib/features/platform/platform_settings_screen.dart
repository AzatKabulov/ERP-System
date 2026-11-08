import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../auth/password_form.dart';
import '../shared/async_section.dart';
import '../shared/loading_skeletons.dart';
import 'platform_models.dart';
import 'platform_repository.dart';
import 'platform_widgets.dart';

/// The owner's own settings: password, light or dark, language, the packages and their prices,
/// and signing out.
class PlatformSettingsScreen extends StatefulWidget {
  const PlatformSettingsScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.languageCode,
    required this.onLanguageChanged,
  });

  final SessionController session;
  final PlatformRepository repository;
  final String languageCode;
  final ValueChanged<String> onLanguageChanged;

  @override
  State<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends State<PlatformSettingsScreen> {
  bool _passwordOpen = false;

  Widget _account(AppLocalizations l) {
    final name = widget.session.user?.displayName ?? '';
    return SurfaceCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppGradients.spotlight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.signedInAs(name),
                  key: const ValueKey('signed-in-as'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(l.pfOwnerRole, style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _password(AppLocalizations l) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('password-toggle'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _passwordOpen = !_passwordOpen),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                AppIcon(AppIcons.lock, size: 20, color: AppColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l.changePasswordTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                AppIcon(
                  _passwordOpen ? AppIcons.chevronDown : AppIcons.chevron,
                  size: 20,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
        if (_passwordOpen)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: PasswordChangeForm(
              session: widget.session,
              onDone: () {
                setState(() => _passwordOpen = false);
                showFeedback(context, l.passwordChangedDone);
              },
            ),
          ),
      ],
    ),
  );

  Widget _appearance(AppLocalizations l) {
    final theme = ThemeScope.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(l.appearanceTitle),
          const SizedBox(height: 4),
          Text(
            l.appearanceHint,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          AppSegmented<String>(
            keyPrefix: 'theme-chip',
            options: [
              ('system', l.themeAuto),
              ('light', l.themeLight),
              ('dark', l.themeDark),
            ],
            value: theme.mode.name,
            onChanged: (v) => theme.setMode(AppThemeMode.values.byName(v)),
          ),
        ],
      ),
    );
  }

  Widget _language(AppLocalizations l) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(l.language),
        const SizedBox(height: 16),
        AppSegmented<String>(
          keyPrefix: 'language-chip',
          options: [('ru', l.languageRussian), ('tk', l.languageTurkmen)],
          value: widget.languageCode,
          onChanged: widget.onLanguageChanged,
        ),
      ],
    ),
  );

  Widget _signOut(AppLocalizations l) => SurfaceCard(
    child: Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Text(
          l.signOutTitle,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        OutlinedButton.icon(
          key: const ValueKey('admin-sign-out'),
          onPressed: widget.session.signOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: BorderSide(color: AppColors.danger.withValues(alpha: 0.3)),
          ),
          icon: const AppIcon(AppIcons.logout),
          label: Text(l.signOut),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final narrow = MediaQuery.sizeOf(context).width < 768;
    const gap = SizedBox(height: 16);
    return SingleChildScrollView(
      padding: pagePadding(context, compact: narrow),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHead(title: l.administration, subtitle: l.pfPlatform),
              const SizedBox(height: 24),
              _account(l),
              gap,
              _password(l),
              gap,
              _appearance(l),
              gap,
              _language(l),
              gap,
              _PackagesCard(repository: widget.repository),
              gap,
              _signOut(l),
            ],
          ),
        ),
      ),
    );
  }
}

/// The packages and their prices. The price is what "add a package" fills in.
class _PackagesCard extends StatefulWidget {
  const _PackagesCard({required this.repository});
  final PlatformRepository repository;

  @override
  State<_PackagesCard> createState() => _PackagesCardState();
}

class _PackagesCardState extends State<_PackagesCard> {
  final _list = GlobalKey<AsyncSectionState<List<PlanRow>>>();

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(l.pfPackages),
          const SizedBox(height: 4),
          Text(
            l.pfPackagesHint,
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          AsyncSection<List<PlanRow>>(
            loadingBuilder: (context) => const RecordListSkeleton(
              rows: 3,
              inCard: false,
              rowHeight: 112,
            ),
            key: _list,
            load: widget.repository.plans,
            builder: (context, plans) => Column(
              children: [
                for (final p in plans)
                  _PlanLine(
                    key: ValueKey('plan-${p.id}'),
                    plan: p,
                    repository: widget.repository,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanLine extends StatefulWidget {
  const _PlanLine({super.key, required this.plan, required this.repository});
  final PlanRow plan;
  final PlatformRepository repository;

  @override
  State<_PlanLine> createState() => _PlanLineState();
}

class _PlanLineState extends State<_PlanLine> {
  late final _price = TextEditingController(text: widget.plan.price ?? '');
  late bool _active = widget.plan.isActive;
  bool _busy = false;
  ApiException? _error;
  bool _saved = false;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _save({bool? active}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      final p = await widget.repository.savePlan(
        widget.plan.id,
        price: active == null ? _price.text.trim() : null,
        isActive: active,
      );
      if (mounted) {
        setState(() {
          _active = p.isActive;
          _saved = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = strings(context);
    final p = widget.plan;
    final name = p.months == null ? l.pfPackageCustom : p.name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.months == null
                      ? name
                      : '$name · ${l.pfPackageMonths(p.months!)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                l.pfPackageOnSale,
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              Switch(
                key: ValueKey('plan-active-${p.id}'),
                value: _active,
                onChanged: _busy ? null : (v) => _save(active: v),
              ),
            ],
          ),
          if (p.months != null)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('plan-price-${p.id}'),
                    controller: _price,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '${l.pfPackagePrice} (${p.currency})',
                      errorText: fieldProblem(l, _error, 'price'),
                    ),
                    onChanged: (_) => setState(() => _saved = false),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  key: ValueKey('plan-save-${p.id}'),
                  onPressed: _busy ? null : () => _save(),
                  child: Text(l.save),
                ),
                if (_saved) ...[
                  const SizedBox(width: 8),
                  AppIcon(AppIcons.checkCircle, color: AppColors.success),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
