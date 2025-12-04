import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StrideSource {
  systemDefault, // 0.78 m
  manual,
  fromHeight,
}

enum WeightSource {
  systemDefault, // 70 kg
  manual,
}

enum Gender {
  male,
  female,
}

class BodyParamsSettings {
  const BodyParamsSettings({
    required this.strideSource,
    required this.weightSource,
    this.gender,
    this.heightCm,
    this.manualStrideMeters,
    this.manualWeightKg,
  });

  final StrideSource strideSource;
  final WeightSource weightSource;
  final Gender? gender;
  final int? heightCm;
  final double? manualStrideMeters;
  final double? manualWeightKg;

  static const BodyParamsSettings defaults = BodyParamsSettings(
    strideSource: StrideSource.systemDefault,
    weightSource: WeightSource.systemDefault,
  );

  BodyParamsSettings copyWith({
    StrideSource? strideSource,
    WeightSource? weightSource,
    Gender? gender,
    bool clearGender = false,
    int? heightCm,
    bool clearHeight = false,
    double? manualStrideMeters,
    bool clearManualStride = false,
    double? manualWeightKg,
    bool clearManualWeight = false,
  }) {
    return BodyParamsSettings(
      strideSource: strideSource ?? this.strideSource,
      weightSource: weightSource ?? this.weightSource,
      gender: clearGender ? null : (gender ?? this.gender),
      heightCm: clearHeight ? null : (heightCm ?? this.heightCm),
      manualStrideMeters: clearManualStride
          ? null
          : (manualStrideMeters ?? this.manualStrideMeters),
      manualWeightKg: clearManualWeight
          ? null
          : (manualWeightKg ?? this.manualWeightKg),
    );
  }
}

class BodyParamsStore {
  static const double defaultStrideMeters = 0.78;
  static const double defaultWeightKg = 70.0;

  static const _keyStrideSource = 'body_stride_source';
  static const _keyWeightSource = 'body_weight_source';
  static const _keyGender = 'body_gender';
  static const _keyHeightCm = 'body_height_cm';
  static const _keyManualStrideMeters = 'body_manual_stride_m';
  static const _keyManualWeightKg = 'body_manual_weight_kg';

  static final ValueNotifier<BodyParamsSettings> settingsNotifier =
      ValueNotifier<BodyParamsSettings>(BodyParamsSettings.defaults);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final strideIndex = prefs.getInt(_keyStrideSource);
    final weightIndex = prefs.getInt(_keyWeightSource);
    final genderIndex = prefs.getInt(_keyGender);
    final heightCm = prefs.getInt(_keyHeightCm);
    final manualStrideMeters = prefs.getDouble(_keyManualStrideMeters);
    final manualWeightKg = prefs.getDouble(_keyManualWeightKg);

    final strideSource = (strideIndex != null &&
            strideIndex >= 0 &&
            strideIndex < StrideSource.values.length)
        ? StrideSource.values[strideIndex]
        : StrideSource.systemDefault;

    final weightSource = (weightIndex != null &&
            weightIndex >= 0 &&
            weightIndex < WeightSource.values.length)
        ? WeightSource.values[weightIndex]
        : WeightSource.systemDefault;

    final gender = (genderIndex != null &&
            genderIndex >= 0 &&
            genderIndex < Gender.values.length)
        ? Gender.values[genderIndex]
        : null;

    final settings = BodyParamsSettings(
      strideSource: strideSource,
      weightSource: weightSource,
      gender: gender,
      heightCm: heightCm,
      manualStrideMeters: manualStrideMeters,
      manualWeightKg: manualWeightKg,
    );

    settingsNotifier.value = settings;
  }

  static Future<void> save(BodyParamsSettings settings) async {
    settingsNotifier.value = settings;
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_keyStrideSource, settings.strideSource.index);
    await prefs.setInt(_keyWeightSource, settings.weightSource.index);

    if (settings.gender != null) {
      await prefs.setInt(_keyGender, settings.gender!.index);
    } else {
      await prefs.remove(_keyGender);
    }

    if (settings.heightCm != null) {
      await prefs.setInt(_keyHeightCm, settings.heightCm!);
    } else {
      await prefs.remove(_keyHeightCm);
    }

    if (settings.manualStrideMeters != null) {
      await prefs.setDouble(
        _keyManualStrideMeters,
        settings.manualStrideMeters!,
      );
    } else {
      await prefs.remove(_keyManualStrideMeters);
    }

    if (settings.manualWeightKg != null) {
      await prefs.setDouble(
        _keyManualWeightKg,
        settings.manualWeightKg!,
      );
    } else {
      await prefs.remove(_keyManualWeightKg);
    }
  }

  static double effectiveStrideMeters(BodyParamsSettings settings) {
    double value;

    switch (settings.strideSource) {
      case StrideSource.systemDefault:
        value = defaultStrideMeters;
        break;
      case StrideSource.manual:
        value = settings.manualStrideMeters ?? defaultStrideMeters;
        break;
      case StrideSource.fromHeight:
        final hCm = settings.heightCm;
        if (hCm == null || hCm <= 0) {
          value = defaultStrideMeters;
        } else {
          final hMeters = hCm / 100.0;
          if (settings.gender == Gender.female) {
            value = 0.413 * hMeters;
          } else if (settings.gender == Gender.male) {
            value = 0.415 * hMeters;
          } else {
            value = defaultStrideMeters;
          }
        }
        break;
    }

    if (value < 0) value = 0;
    if (value > 2) value = 2;
    value = double.parse(value.toStringAsFixed(2));

    return value;
  }


  static double effectiveWeightKg(BodyParamsSettings settings) {
    double value;

    switch (settings.weightSource) {
      case WeightSource.systemDefault:
        value = defaultWeightKg;
        break;
      case WeightSource.manual:
        value = settings.manualWeightKg ?? defaultWeightKg;
        break;
    }

    if (value < 0) value = 0;
    if (value > 300) value = 300;
    value = double.parse(value.toStringAsFixed(2));

    return value;
  }

}
