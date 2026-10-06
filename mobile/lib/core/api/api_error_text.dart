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
  'max_whole_digits' => l.fieldTooManyDecimals,
  'min_value' || 'max_value' => l.fieldOutOfRange,
  'quantity_precision' => l.fieldQuantityPrecision,
  _ => l.fieldInvalid,
};

/// First readable message for [field], or null when it has no error.
String? fieldError(AppLocalizations l, ApiException? e, String field) {
  final list = e?.fields[field];
  if (list == null || list.isEmpty) return null;
  return fieldErrorText(l, list.first);
}
