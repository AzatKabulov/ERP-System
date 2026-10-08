import '../../l10n/app_localizations.dart';
import 'api_exception.dart';

/// Turns a server error code into a message in the interface language. The
/// server's own text is English and is never shown to users.
String apiErrorText(AppLocalizations l, ApiException e) {
  switch (e.code) {
    case 'invalid_credentials':
      return l.errorInvalidCredentials;
    case 'rate_limited':
      return l.errorRateLimited;
    case 'permission_denied':
      return l.errorPermission;
    case 'not_found':
      return l.errorNotFound;
    case 'last_owner':
      return l.errorLastOwner;
    case 'location_not_permitted':
      return l.errorLocationNotPermitted;
    case 'invalid_reset_code':
      return l.errorInvalidResetCode;
    case 'invalid_old_password':
      return l.errorInvalidOldPassword;
    case 'session_expired':
    case 'session_revoked':
    case 'invalid_token':
    case 'not_authenticated':
      return l.sessionExpiredNotice;
    case 'barcode_not_found':
      return l.errorBarcodeNotFound;
    case 'unit_in_use':
      return l.errorUnitInUse;
    case 'insufficient_stock':
      return l.errorInsufficientStock;
    case 'opening_stock_exists':
      return l.errorOpeningExists;
    case 'product_archived':
      return l.errorProductArchived;
    case 'location_inactive':
      return l.errorLocationInactive;
    case 'over_receipt':
      return l.errorOverReceipt;
    case 'order_not_draft':
      return l.errorOrderNotDraft;
    case 'order_not_receivable':
      return l.errorOrderNotReceivable;
    case 'order_not_cancellable':
      return l.errorOrderNotCancellable;
    case 'order_has_no_lines':
      return l.errorOrderNoLines;
    case 'transfer_not_receivable':
      return l.errorTransferNotReceivable;
    case 'transfer_not_cancellable':
      return l.errorTransferNotCancellable;
    case 'count_not_open':
      return l.errorCountNotOpen;
    case 'count_empty':
      return l.errorCountEmpty;
    case 'count_not_submitted':
      return l.errorCountNotSubmitted;
    case 'count_not_cancellable':
      return l.errorCountNotCancellable;
    case 'over_return':
      return l.errorOverReturn;
    case 'return_window_expired':
      return l.errorReturnWindowExpired('${e.params['until'] ?? ''}');
    case 'returns_not_accepted':
      return l.errorReturnsNotAccepted;
    case 'over_inspection':
      return l.errorOverInspection;
    case 'not_awaiting_inspection':
      return l.errorNotAwaitingInspection;
    case 'file_too_large':
      return l.errorFileTooLarge;
    case 'file_type_not_allowed':
      return l.errorFileType;
    case 'file_required':
      return l.errorFileRequired;
    case 'future_date':
      return l.errorFutureDate;
    case 'expense_void':
      return l.errorExpenseVoid;
    case 'already_void':
      return l.errorAlreadyVoid;
    case 'no_warranty':
      return l.errorNoWarranty;
    case 'warranty_expired':
      return l.errorWarrantyExpired('${e.params['until'] ?? ''}');
    case 'claim_closed':
      return l.errorClaimClosed;
    case 'import_too_large':
      return l.errorImportTooLarge;
    case 'invalid_header':
      return l.errorImportHeader;
    case 'import_invalid':
      return l.errorImportInvalid;
    case 'range_too_long':
      return l.errorRangeTooLong;
    case 'over_claim':
      return l.errorOverClaim;
    case 'invalid_file':
      return l.errorInvalidFile;
    case 'file_missing':
      return l.errorFileMissing;
    case 'validation_error':
      return l.errorValidation;
    case 'network':
      return l.errorNetwork;
    case 'timeout':
      return l.errorTimeout;
    case 'server_error':
    case 'malformed_response':
      return l.errorServer;
  }
  return switch (e.kind) {
    ApiErrorKind.network => l.errorNetwork,
    ApiErrorKind.timeout => l.errorTimeout,
    ApiErrorKind.server => l.errorServer,
    ApiErrorKind.unauthorized => l.sessionExpiredNotice,
    _ => l.errorUnknown,
  };
}

/// Message for one field-level error (a rejected input), by its code.
String fieldErrorText(AppLocalizations l, FieldError e) => switch (e.code) {
  'required' || 'blank' || 'null' => l.fieldRequired,
  'username_taken' => l.fieldUsernameTaken,
  'email_taken' => l.fieldEmailTaken,
  'invalid_username' => l.fieldInvalidUsername,
  'name_taken' => l.fieldNameTaken,
  'locations_required' => l.fieldLocationsRequired,
  'invalid_location' => l.fieldInvalidLocation,
  'password_too_short' => l.passwordTooShort,
  'password_too_common' => l.passwordTooCommon,
  'password_entirely_numeric' => l.passwordNumeric,
  'password_too_similar' => l.passwordSimilar,
  'invalid_old_password' => l.errorInvalidOldPassword,
  'sku_taken' => l.fieldSkuTaken,
  'barcode_taken' => l.fieldBarcodeTaken,
  'max_decimal_places' ||
  'max_digits' ||
  'max_whole_digits' ||
  'too_many_decimals' => l.fieldTooManyDecimals,
  'min_value' ||
  'max_value' ||
  'negative_number' ||
  'out_of_range' => l.fieldOutOfRange,
  'quantity_precision' => l.fieldQuantityPrecision,
  'duplicate_product' || 'duplicate_line' => l.fieldDuplicateProduct,
  'target_below_minimum' => l.errorTargetBelowMinimum,
  'unknown_unit' => l.importErrUnknownUnit,
  'sku_exists' => l.importErrSkuExists,
  'sku_duplicate_in_file' => l.importErrSkuDuplicate,
  'barcode_exists' => l.fieldBarcodeTaken,
  'barcode_duplicate_in_file' => l.importErrBarcodeDuplicate,
  'invalid_currency' => l.importErrCurrency,
  'value_out_of_range' => l.fieldOutOfRange,
  'too_long' => l.importErrTooLong,
  'invalid_number' => l.fieldInvalid,
  'future_date' => l.errorFutureDate,
  _ => l.fieldInvalid,
};

/// First readable message for [field], or null when it has no error.
String? fieldError(AppLocalizations l, ApiException? e, String field) {
  final list = e?.fields[field];
  if (list == null || list.isEmpty) return null;
  return fieldErrorText(l, list.first);
}
