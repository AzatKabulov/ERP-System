import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_localizations_tk.dart';

// Flutter has no built-in tk delegates. This adapter covers the controls used
// in this prototype. Audit and extend it before adding date/time pickers.
class TurkmenMaterialLocalizations extends DefaultMaterialLocalizations {
  const TurkmenMaterialLocalizations();

  @override
  String get openAppDrawerTooltip =>
      AppLocalizationsTk().widgetOpenAppDrawerTooltip;

  @override
  String get backButtonTooltip => AppLocalizationsTk().widgetBackButtonTooltip;

  @override
  String get clearButtonTooltip =>
      AppLocalizationsTk().widgetClearButtonTooltip;

  @override
  String get closeButtonTooltip =>
      AppLocalizationsTk().widgetCloseButtonTooltip;

  @override
  String get deleteButtonTooltip =>
      AppLocalizationsTk().widgetDeleteButtonTooltip;

  @override
  String get moreButtonTooltip => AppLocalizationsTk().widgetMoreButtonTooltip;

  @override
  String get nextPageTooltip => AppLocalizationsTk().widgetNextPageTooltip;

  @override
  String get previousPageTooltip =>
      AppLocalizationsTk().widgetPreviousPageTooltip;

  @override
  String get firstPageTooltip => AppLocalizationsTk().widgetFirstPageTooltip;

  @override
  String get lastPageTooltip => AppLocalizationsTk().widgetLastPageTooltip;

  @override
  String get showMenuTooltip => AppLocalizationsTk().widgetShowMenuTooltip;

  @override
  String get drawerLabel => AppLocalizationsTk().widgetDrawerLabel;

  @override
  String get menuBarMenuLabel => AppLocalizationsTk().widgetMenuBarMenuLabel;

  @override
  String get popupMenuLabel => AppLocalizationsTk().widgetPopupMenuLabel;

  @override
  String get dialogLabel => AppLocalizationsTk().widgetDialogLabel;

  @override
  String get alertDialogLabel => AppLocalizationsTk().widgetAlertDialogLabel;

  @override
  String get searchFieldLabel => AppLocalizationsTk().widgetSearchFieldLabel;

  @override
  String get scrimLabel => AppLocalizationsTk().widgetScrimLabel;

  @override
  String get bottomSheetLabel => AppLocalizationsTk().widgetBottomSheetLabel;

  @override
  String get rowsPerPageTitle => AppLocalizationsTk().widgetRowsPerPageTitle;

  @override
  String get cancelButtonLabel => AppLocalizationsTk().widgetCancelButtonLabel;

  @override
  String get closeButtonLabel => AppLocalizationsTk().widgetCloseButtonLabel;

  @override
  String get continueButtonLabel =>
      AppLocalizationsTk().widgetContinueButtonLabel;

  @override
  String get copyButtonLabel => AppLocalizationsTk().widgetCopyButtonLabel;

  @override
  String get cutButtonLabel => AppLocalizationsTk().widgetCutButtonLabel;

  @override
  String get pasteButtonLabel => AppLocalizationsTk().widgetPasteButtonLabel;

  @override
  String get selectAllButtonLabel =>
      AppLocalizationsTk().widgetSelectAllButtonLabel;

  @override
  String get okButtonLabel => AppLocalizationsTk().widgetOkButtonLabel;

  @override
  String get scanTextButtonLabel =>
      AppLocalizationsTk().widgetScanTextButtonLabel;

  @override
  String get lookUpButtonLabel => AppLocalizationsTk().widgetLookUpButtonLabel;

  @override
  String get searchWebButtonLabel =>
      AppLocalizationsTk().widgetSearchWebButtonLabel;

  @override
  String get shareButtonLabel => AppLocalizationsTk().widgetShareButtonLabel;

  @override
  String get modalBarrierDismissLabel =>
      AppLocalizationsTk().widgetModalBarrierDismissLabel;

  @override
  String get menuDismissLabel => AppLocalizationsTk().widgetMenuDismissLabel;

  @override
  String get expandedIconTapHint =>
      AppLocalizationsTk().widgetExpandedIconTapHint;

  @override
  String get collapsedIconTapHint =>
      AppLocalizationsTk().widgetCollapsedIconTapHint;

  @override
  String get expansionTileExpandedHint =>
      AppLocalizationsTk().widgetExpansionTileExpandedHint;

  @override
  String get expansionTileCollapsedHint =>
      AppLocalizationsTk().widgetExpansionTileCollapsedHint;

  @override
  String get expansionTileExpandedTapHint =>
      AppLocalizationsTk().widgetExpansionTileExpandedTapHint;

  @override
  String get expansionTileCollapsedTapHint =>
      AppLocalizationsTk().widgetExpansionTileCollapsedTapHint;

  @override
  String get expandedHint => AppLocalizationsTk().widgetExpandedHint;

  @override
  String get collapsedHint => AppLocalizationsTk().widgetCollapsedHint;

  @override
  String get refreshIndicatorSemanticLabel =>
      AppLocalizationsTk().widgetRefreshIndicatorSemanticLabel;

  @override
  String tabLabel({required int tabIndex, required int tabCount}) =>
      AppLocalizationsTk().widgetTabLabel(tabIndex, tabCount);

  @override
  String selectedRowCountTitle(int selectedRowCount) =>
      AppLocalizationsTk().widgetSelectedRows(selectedRowCount);

  @override
  String scrimOnTapHint(String modalRouteContentName) =>
      AppLocalizationsTk().widgetDismissHint(modalRouteContentName);
}

class TurkmenCupertinoLocalizations extends DefaultCupertinoLocalizations {
  const TurkmenCupertinoLocalizations();

  @override
  String get copyButtonLabel => AppLocalizationsTk().widgetCopyButtonLabel;

  @override
  String get cutButtonLabel => AppLocalizationsTk().widgetCutButtonLabel;

  @override
  String get pasteButtonLabel => AppLocalizationsTk().widgetPasteButtonLabel;

  @override
  String get selectAllButtonLabel =>
      AppLocalizationsTk().widgetSelectAllButtonLabel;

  @override
  String get lookUpButtonLabel => AppLocalizationsTk().widgetLookUpButtonLabel;

  @override
  String get searchWebButtonLabel =>
      AppLocalizationsTk().widgetSearchWebButtonLabel;

  @override
  String get shareButtonLabel => AppLocalizationsTk().widgetShareButtonLabel;

  @override
  String get modalBarrierDismissLabel =>
      AppLocalizationsTk().widgetModalBarrierDismissLabel;

  @override
  String get menuDismissLabel => AppLocalizationsTk().widgetMenuDismissLabel;

  @override
  String get cancelButtonLabel => AppLocalizationsTk().widgetCancelButtonLabel;

  @override
  String get backButtonLabel => AppLocalizationsTk().widgetBackButtonLabel;

  @override
  String get clearButtonLabel => AppLocalizationsTk().widgetClearButtonLabel;

  @override
  String get noSpellCheckReplacementsLabel =>
      AppLocalizationsTk().widgetNoSpellCheckReplacementsLabel;

  @override
  String get searchTextFieldPlaceholderLabel =>
      AppLocalizationsTk().widgetSearchTextFieldPlaceholderLabel;

  @override
  String get expansionTileExpandedHint =>
      AppLocalizationsTk().widgetExpansionTileExpandedHint;

  @override
  String get expansionTileCollapsedHint =>
      AppLocalizationsTk().widgetExpansionTileCollapsedHint;

  @override
  String get expansionTileExpandedTapHint =>
      AppLocalizationsTk().widgetExpansionTileExpandedTapHint;

  @override
  String get expansionTileCollapsedTapHint =>
      AppLocalizationsTk().widgetExpansionTileCollapsedTapHint;

  @override
  String get expandedHint => AppLocalizationsTk().widgetExpandedHint;

  @override
  String get collapsedHint => AppLocalizationsTk().widgetCollapsedHint;
}

class TurkmenMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const TurkmenMaterialDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tk';
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(
        const TurkmenMaterialLocalizations(),
      );
  @override
  bool shouldReload(TurkmenMaterialDelegate old) => false;
}

class TurkmenCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const TurkmenCupertinoDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tk';
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      SynchronousFuture<CupertinoLocalizations>(
        const TurkmenCupertinoLocalizations(),
      );
  @override
  bool shouldReload(TurkmenCupertinoDelegate old) => false;
}

class TurkmenWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const TurkmenWidgetsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tk';
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      SynchronousFuture<WidgetsLocalizations>(
        const DefaultWidgetsLocalizations(),
      );
  @override
  bool shouldReload(TurkmenWidgetsDelegate old) => false;
}
