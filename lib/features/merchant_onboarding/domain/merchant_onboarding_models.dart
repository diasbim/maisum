import '../../business_profile/domain/business_profile.dart';

enum MerchantOnboardingStep {
  verifyPhone,
  businessType,
  businessInfo,
  location,
  workingHours,
  services,
  review,
}

extension MerchantOnboardingStepX on MerchantOnboardingStep {
  int get number => index + 1;
  int get total => MerchantOnboardingStep.values.length;

  String get route => switch (this) {
        MerchantOnboardingStep.verifyPhone => '/login',
        MerchantOnboardingStep.businessType => '/merchant-onboarding/type',
        MerchantOnboardingStep.businessInfo => '/merchant-onboarding/info',
        MerchantOnboardingStep.location => '/merchant-onboarding/location',
        MerchantOnboardingStep.workingHours => '/merchant-onboarding/hours',
        MerchantOnboardingStep.services => '/merchant-onboarding/services',
        MerchantOnboardingStep.review => '/merchant-onboarding/review',
      };
}

class MerchantLocation {
  const MerchantLocation({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory MerchantLocation.fromJson(Map<String, dynamic> json) {
    return MerchantLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    );
  }
}

class WorkingHours {
  const WorkingHours({
    required this.weekday,
    required this.openTime,
    required this.closeTime,
    required this.isOpen,
  });

  final int weekday;
  final String openTime;
  final String closeTime;
  final bool isOpen;

  WorkingHours copyWith({
    int? weekday,
    String? openTime,
    String? closeTime,
    bool? isOpen,
  }) {
    return WorkingHours(
      weekday: weekday ?? this.weekday,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      isOpen: isOpen ?? this.isOpen,
    );
  }

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'open_time': openTime,
        'close_time': closeTime,
        'is_open': isOpen,
      };

  factory WorkingHours.fromJson(Map<String, dynamic> json) {
    return WorkingHours(
      weekday: (json['weekday'] as num?)?.toInt() ?? 0,
      openTime: (json['open_time'] as String?) ?? '',
      closeTime: (json['close_time'] as String?) ?? '',
      isOpen: (json['is_open'] as bool?) ?? false,
    );
  }
}

class MerchantService {
  const MerchantService({
    required this.id,
    required this.name,
    this.iconKey,
    this.itemKind = BusinessItemKind.service,
    this.isCustom = false,
  });

  final String id;
  final String name;
  final String? iconKey;
  final BusinessItemKind itemKind;
  final bool isCustom;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (iconKey != null) 'icon_key': iconKey,
        'item_type': itemKind.name,
        'is_custom': isCustom,
      };

  factory MerchantService.fromJson(Map<String, dynamic> json) {
    return MerchantService(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      iconKey: json['icon_key'] as String?,
      itemKind: _readItemKind(json['item_type'] ?? json['type']),
      isCustom: (json['is_custom'] as bool?) ?? false,
    );
  }

  static BusinessItemKind _readItemKind(Object? raw) {
    return raw?.toString().trim().toLowerCase() == 'product'
        ? BusinessItemKind.product
        : BusinessItemKind.service;
  }
}

class MerchantBusinessType {
  const MerchantBusinessType({
    required this.id,
    required this.label,
    this.iconKey,
  });

  final String id;
  final String label;
  final String? iconKey;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (iconKey != null) 'icon_key': iconKey,
      };

  factory MerchantBusinessType.fromJson(Map<String, dynamic> json) {
    return MerchantBusinessType(
      id: ((json['id'] ?? json['value']) as String?)?.trim() ?? '',
      label: ((json['label'] ?? json['name']) as String?)?.trim() ?? '',
      iconKey: (json['icon_key'] ?? json['iconKey']) as String?,
    );
  }
}

class MerchantOnboardingConfig {
  const MerchantOnboardingConfig({
    this.businessTypes = const [],
    this.serviceSuggestions = const [],
    this.itemSuggestionsByBusinessType = const {},
    this.defaultWorkingHours = const {},
    this.weekdayLabels = const {},
  });

  final List<MerchantBusinessType> businessTypes;
  final List<MerchantService> serviceSuggestions;
  final Map<String, List<MerchantService>> itemSuggestionsByBusinessType;
  final Map<int, WorkingHours> defaultWorkingHours;
  final Map<int, String> weekdayLabels;

  static final fallback = MerchantOnboardingConfig(
    businessTypes: [
      for (final profile in BusinessProfiles.all)
        MerchantBusinessType(
          id: profile.id,
          label: profile.label,
          iconKey: profile.iconKey,
        ),
    ],
    itemSuggestionsByBusinessType: {
      for (final profile in BusinessProfiles.all)
        profile.id: [
          for (final item in profile.itemPresets)
            MerchantService(
              id: item.id,
              name: item.name,
              iconKey: item.iconKey,
              itemKind: item.kind,
            ),
        ],
    },
    defaultWorkingHours: {
      1: const WorkingHours(
        weekday: 1,
        openTime: '09:00',
        closeTime: '18:00',
        isOpen: true,
      ),
      2: const WorkingHours(
        weekday: 2,
        openTime: '09:00',
        closeTime: '18:00',
        isOpen: true,
      ),
      3: const WorkingHours(
        weekday: 3,
        openTime: '09:00',
        closeTime: '18:00',
        isOpen: true,
      ),
      4: const WorkingHours(
        weekday: 4,
        openTime: '09:00',
        closeTime: '18:00',
        isOpen: true,
      ),
      5: const WorkingHours(
        weekday: 5,
        openTime: '09:00',
        closeTime: '18:00',
        isOpen: true,
      ),
      6: const WorkingHours(
        weekday: 6,
        openTime: '09:00',
        closeTime: '16:00',
        isOpen: true,
      ),
    },
    weekdayLabels: {
      1: 'Segunda',
      2: 'Terca',
      3: 'Quarta',
      4: 'Quinta',
      5: 'Sexta',
      6: 'Sabado',
      7: 'Domingo',
    },
  );

  factory MerchantOnboardingConfig.fromJson(Map<String, dynamic> json) {
    return MerchantOnboardingConfig(
      businessTypes: _readBusinessTypes(json['business_types']),
      serviceSuggestions:
          _readServices(json['service_suggestions'] ?? json['services']),
      itemSuggestionsByBusinessType: _readServicesByBusinessType(
        json['item_suggestions_by_business_type'] ??
            json['service_suggestions_by_business_type'],
      ),
      defaultWorkingHours: _readWorkingHours(json['default_working_hours']),
      weekdayLabels: _readWeekdayLabels(json['weekday_labels']),
    );
  }

  MerchantOnboardingConfig withBuiltInProfiles() {
    final knownIds = businessTypes.map((type) => type.id).toSet();
    return MerchantOnboardingConfig(
      businessTypes: [
        ...businessTypes,
        ...fallback.businessTypes.where((type) => !knownIds.contains(type.id)),
      ],
      serviceSuggestions: serviceSuggestions,
      itemSuggestionsByBusinessType: {
        ...fallback.itemSuggestionsByBusinessType,
        ...itemSuggestionsByBusinessType,
      },
      defaultWorkingHours: defaultWorkingHours.isEmpty
          ? fallback.defaultWorkingHours
          : defaultWorkingHours,
      weekdayLabels:
          weekdayLabels.isEmpty ? fallback.weekdayLabels : weekdayLabels,
    );
  }

  List<MerchantService> suggestionsForBusinessType(String? businessType) {
    final normalizedType = businessType?.trim() ?? '';
    final configured = itemSuggestionsByBusinessType[normalizedType];
    if (configured != null) return configured;

    final profile = BusinessProfiles.resolve(normalizedType);
    if (profile.id != BusinessProfiles.generic.id) {
      return [
        for (final item in profile.itemPresets)
          MerchantService(
            id: item.id,
            name: item.name,
            iconKey: item.iconKey,
            itemKind: item.kind,
          ),
      ];
    }
    return serviceSuggestions;
  }

  static List<MerchantBusinessType> _readBusinessTypes(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map(_asStringKeyMap)
        .nonNulls
        .map(MerchantBusinessType.fromJson)
        .where((type) => type.id.isNotEmpty && type.label.isNotEmpty)
        .toList();
  }

  static List<MerchantService> _readServices(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map(_asStringKeyMap)
        .nonNulls
        .map(MerchantService.fromJson)
        .where((service) => service.id.isNotEmpty && service.name.isNotEmpty)
        .toList();
  }

  static Map<String, List<MerchantService>> _readServicesByBusinessType(
    Object? raw,
  ) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key.toString().trim().isNotEmpty)
          entry.key.toString().trim(): _readServices(entry.value),
    };
  }

  static Map<int, WorkingHours> _readWorkingHours(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) {
        final data = _asStringKeyMap(value) ?? const <String, dynamic>{};
        final weekday = int.tryParse(key.toString()) ??
            (data['weekday'] as num?)?.toInt() ??
            0;
        return MapEntry(
          weekday,
          WorkingHours.fromJson({...data, 'weekday': weekday}),
        );
      })
        ..removeWhere((key, _) => key <= 0);
    }

    if (raw is List) {
      return {
        for (final data in raw.map(_asStringKeyMap).nonNulls)
          if ((data['weekday'] as num?)?.toInt() case final weekday?
              when weekday > 0)
            weekday: WorkingHours.fromJson(data),
      };
    }

    return const {};
  }

  static Map<int, String> _readWeekdayLabels(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map((key, value) => MapEntry(
          int.tryParse(key.toString()) ?? 0,
          value.toString(),
        ))
      ..removeWhere((key, value) => key <= 0 || value.trim().isEmpty);
  }

  static Map<String, dynamic>? _asStringKeyMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}

class MerchantDraft {
  const MerchantDraft({
    this.businessType,
    this.businessName,
    this.phone,
    this.city,
    this.district,
    this.location,
    this.address,
    this.reference,
    this.workingHours = const {},
    this.services = const [],
  });

  final String? businessType;
  final String? businessName;
  final String? phone;
  final String? city;
  final String? district;
  final MerchantLocation? location;
  final String? address;
  final String? reference;
  final Map<int, WorkingHours> workingHours;
  final List<MerchantService> services;

  MerchantDraft copyWith({
    String? businessType,
    String? businessName,
    String? phone,
    String? city,
    String? district,
    MerchantLocation? location,
    String? address,
    String? reference,
    Map<int, WorkingHours>? workingHours,
    List<MerchantService>? services,
    bool clearLocation = false,
  }) {
    return MerchantDraft(
      businessType: businessType ?? this.businessType,
      businessName: businessName ?? this.businessName,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      district: district ?? this.district,
      location: clearLocation ? null : location ?? this.location,
      address: address ?? this.address,
      reference: reference ?? this.reference,
      workingHours: workingHours ?? this.workingHours,
      services: services ?? this.services,
    );
  }

  MerchantDraft mergeMissing(MerchantDraft other) {
    return MerchantDraft(
      businessType: businessType ?? other.businessType,
      businessName: businessName ?? other.businessName,
      phone: phone ?? other.phone,
      city: city ?? other.city,
      district: district ?? other.district,
      location: location ?? other.location,
      address: address ?? other.address,
      reference: reference ?? other.reference,
      workingHours: workingHours.isNotEmpty ? workingHours : other.workingHours,
      services: services.isNotEmpty ? services : other.services,
    );
  }

  Map<String, dynamic> toJson() => {
        if (businessType != null) 'business_type': businessType,
        if (businessName != null) 'business_name': businessName,
        if (phone != null) 'phone': phone,
        if (city != null) 'city': city,
        if (district != null) 'district': district,
        if (location != null) 'location': location!.toJson(),
        if (address != null) 'address': address,
        if (reference != null) 'reference': reference,
        'working_hours': workingHours.map(
          (key, value) => MapEntry(key.toString(), value.toJson()),
        ),
        'services': services.map((service) => service.toJson()).toList(),
      };

  factory MerchantDraft.fromJson(Map<String, dynamic> json) {
    final rawHours = json['working_hours'] as Map<String, dynamic>? ?? const {};
    final rawServices = json['services'] as List<dynamic>? ?? const [];
    return MerchantDraft(
      businessType: json['business_type'] as String?,
      businessName: json['business_name'] as String?,
      phone: json['phone'] as String?,
      city: json['city'] as String?,
      district: json['district'] as String?,
      location: json['location'] is Map<String, dynamic>
          ? MerchantLocation.fromJson(json['location'] as Map<String, dynamic>)
          : null,
      address: json['address'] as String?,
      reference: json['reference'] as String?,
      workingHours: rawHours.map(
        (key, value) => MapEntry(
          int.tryParse(key) ?? 1,
          WorkingHours.fromJson(value as Map<String, dynamic>),
        ),
      ),
      services: rawServices
          .whereType<Map<String, dynamic>>()
          .map(MerchantService.fromJson)
          .where((service) => service.name.trim().isNotEmpty)
          .toList(),
    );
  }

  factory MerchantDraft.empty({String? phone}) {
    return MerchantDraft(
      phone: phone,
    );
  }
}

MerchantDraft merchantDraftFromBusinessData(
  Map<String, dynamic> data, {
  String? fallbackPhone,
}) {
  return MerchantDraft(
    businessType: data['business_type'] as String?,
    businessName: data['merchant_name'] as String?,
    phone: (data['phone'] as String?) ?? fallbackPhone,
    city: data['city'] as String?,
    district: data['district'] as String?,
    location: data['location'] is Map
        ? MerchantLocation.fromJson(_asStringKeyMap(data['location'])!)
        : null,
    address: data['address'] as String?,
    reference: data['reference'] as String?,
    workingHours: readMerchantWorkingHours(data['working_hours']),
    services: readMerchantServices(data['services']),
  );
}

Map<int, WorkingHours> readMerchantWorkingHours(Object? raw) {
  if (raw is! Map) return const {};
  return raw.map(
    (key, value) => MapEntry(
      int.tryParse(key.toString()) ?? 0,
      WorkingHours.fromJson(_asStringKeyMap(value) ?? const {}),
    ),
  )..removeWhere((key, _) => key <= 0);
}

List<MerchantService> readMerchantServices(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map(_asStringKeyMap)
      .nonNulls
      .map(MerchantService.fromJson)
      .where((service) => service.name.trim().isNotEmpty)
      .toList();
}

Map<String, dynamic>? _asStringKeyMap(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}
