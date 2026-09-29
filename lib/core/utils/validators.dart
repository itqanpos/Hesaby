// lib/core/utils/validators.dart
/// Validation outcomes produced by [Validators].
///
/// The presentation layer maps these to localized messages.
enum ValidationError {
  required,
  invalidEmail,
  invalidPhone,
  tooShort,
  tooLong,
  invalidNumber,
  mustBePositive,
}

/// Reusable, localization-agnostic form validation.
abstract final class Validators {
  static const int defaultMinLength = 3;
  static const int defaultMaxLength = 255;

  static final RegExp _emailPattern = RegExp(
    r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$',
  );

  /// Matches Egyptian mobile numbers in local or international form.
  static final RegExp _egyptianPhonePattern = RegExp(
    r'^(?:\+20|0)?1[0125]\d{8}$',
  );

  static ValidationError? required(String? value) =>
      (value == null || value.trim().isEmpty) ? ValidationError.required : null;

  static ValidationError? email(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return ValidationError.required;
    }
    return _emailPattern.hasMatch(trimmed)
        ? null
        : ValidationError.invalidEmail;
  }

  static ValidationError? phone(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return ValidationError.required;
    }
    final String normalized = trimmed.replaceAll(RegExp(r'[\s-]'), '');
    return _egyptianPhonePattern.hasMatch(normalized)
        ? null
        : ValidationError.invalidPhone;
  }

  static ValidationError? minLength(
    String? value, [
    int minLength = defaultMinLength,
  ]) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return ValidationError.required;
    }
    return trimmed.length < minLength ? ValidationError.tooShort : null;
  }

  static ValidationError? maxLength(
    String? value, [
    int maxLength = defaultMaxLength,
  ]) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return ValidationError.required;
    }
    return trimmed.length > maxLength ? ValidationError.tooLong : null;
  }

  static ValidationError? positiveNumber(String? value) {
    final String trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return ValidationError.required;
    }
    final num? parsed = num.tryParse(trimmed);
    if (parsed == null) {
      return ValidationError.invalidNumber;
    }
    return parsed <= 0 ? ValidationError.mustBePositive : null;
  }

  /// Returns the first non-null error in [errors], or `null` if all passed.
  static ValidationError? firstError(List<ValidationError?> errors) {
    for (final ValidationError? error in errors) {
      if (error != null) {
        return error;
      }
    }
    return null;
  }
}
