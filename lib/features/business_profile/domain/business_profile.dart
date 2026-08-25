enum BusinessItemKind { service, product }

class BusinessItemPreset {
  const BusinessItemPreset({
    required this.id,
    required this.name,
    required this.kind,
    this.iconKey,
  });

  final String id;
  final String name;
  final BusinessItemKind kind;
  final String? iconKey;
}

class BusinessTerminology {
  const BusinessTerminology({
    this.business = 'negocio',
    this.businessCode = 'Codigo do negocio',
    this.transaction = 'venda',
    this.appointment = 'marcacao',
    this.appointments = 'marcacoes',
    this.nextVisit = 'proxima visita',
  });

  final String business;
  final String businessCode;
  final String transaction;
  final String appointment;
  final String appointments;
  final String nextVisit;
}

class BusinessCapabilities {
  const BusinessCapabilities({
    required this.services,
    required this.products,
    required this.appointments,
    this.staff = true,
  });

  final bool services;
  final bool products;
  final bool appointments;
  final bool staff;
}

class BusinessRetentionDefaults {
  const BusinessRetentionDefaults({
    required this.activeDays,
    required this.attentionDays,
    required this.riskDays,
  })  : assert(activeDays < attentionDays),
        assert(attentionDays < riskDays);

  final int activeDays;
  final int attentionDays;
  final int riskDays;
}

class BusinessLoyaltyDefaults {
  const BusinessLoyaltyDefaults({
    this.pointsPerMzn = 100,
    this.quickAmounts = const [100, 200, 500, 1000],
  });

  final int pointsPerMzn;
  final List<int> quickAmounts;
}

class BusinessProfile {
  const BusinessProfile({
    required this.id,
    required this.label,
    required this.iconKey,
    required this.capabilities,
    this.terminology = const BusinessTerminology(),
    this.retention = const BusinessRetentionDefaults(
      activeDays: 30,
      attentionDays: 60,
      riskDays: 90,
    ),
    this.loyalty = const BusinessLoyaltyDefaults(),
    this.appointmentIntervalsDays = const [7, 14, 30],
    this.defaultAppointmentHour = 10,
    this.itemPresets = const [],
  });

  final String id;
  final String label;
  final String iconKey;
  final BusinessCapabilities capabilities;
  final BusinessTerminology terminology;
  final BusinessRetentionDefaults retention;
  final BusinessLoyaltyDefaults loyalty;
  final List<int> appointmentIntervalsDays;
  final int defaultAppointmentHour;
  final List<BusinessItemPreset> itemPresets;

  BusinessProfile withMerchantOverrides(Map<String, dynamic> businessData) {
    final loyaltyData = _asStringMap(businessData['loyalty_config']);
    final retentionData = _asStringMap(businessData['retention_config']);
    final appointmentData = _asStringMap(businessData['appointment_config']);

    final pointsPerMzn = _positiveInt(loyaltyData?['points_per_mzn']);
    final quickAmounts = _positiveIntList(loyaltyData?['quick_amounts']);
    final activeDays = _positiveInt(retentionData?['active_days']);
    final attentionDays = _positiveInt(retentionData?['attention_days']);
    final riskDays = _positiveInt(retentionData?['risk_days']);
    final defaultHour = _nonNegativeInt(appointmentData?['default_hour']);
    final intervals =
        _positiveIntList(appointmentData?['quick_intervals_days']);

    final resolvedActive = activeDays ?? retention.activeDays;
    final resolvedAttention = attentionDays ?? retention.attentionDays;
    final resolvedRisk = riskDays ?? retention.riskDays;
    final validRetention =
        resolvedActive < resolvedAttention && resolvedAttention < resolvedRisk;

    return BusinessProfile(
      id: id,
      label: label,
      iconKey: iconKey,
      capabilities: capabilities,
      terminology: terminology,
      retention: validRetention
          ? BusinessRetentionDefaults(
              activeDays: resolvedActive,
              attentionDays: resolvedAttention,
              riskDays: resolvedRisk,
            )
          : retention,
      loyalty: BusinessLoyaltyDefaults(
        pointsPerMzn: pointsPerMzn ?? loyalty.pointsPerMzn,
        quickAmounts:
            quickAmounts.isEmpty ? loyalty.quickAmounts : quickAmounts,
      ),
      appointmentIntervalsDays:
          intervals.isEmpty ? appointmentIntervalsDays : intervals,
      defaultAppointmentHour: defaultHour != null && defaultHour <= 23
          ? defaultHour
          : defaultAppointmentHour,
      itemPresets: itemPresets,
    );
  }

  static Map<String, dynamic>? _asStringMap(Object? raw) {
    if (raw is! Map) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  static int? _positiveInt(Object? raw) {
    final value =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    return value != null && value > 0 ? value : null;
  }

  static int? _nonNegativeInt(Object? raw) {
    final value =
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    return value != null && value >= 0 ? value : null;
  }

  static List<int> _positiveIntList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(_positiveInt).nonNulls.toSet().toList()..sort();
  }
}

class BusinessProfiles {
  const BusinessProfiles._();

  static const int schemaVersion = 1;

  static const genericRetention = BusinessRetentionDefaults(
    activeDays: 30,
    attentionDays: 60,
    riskDays: 90,
  );

  static const generic = BusinessProfile(
    id: 'other',
    label: 'Outro negocio local',
    iconKey: 'store',
    capabilities: BusinessCapabilities(
      services: true,
      products: true,
      appointments: false,
    ),
    retention: genericRetention,
  );

  static const all = <BusinessProfile>[
    BusinessProfile(
      id: 'barbershop',
      label: 'Barbearia',
      iconKey: 'barbershop',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: true,
      ),
      terminology: BusinessTerminology(
        appointment: 'corte',
        appointments: 'cortes',
        nextVisit: 'proximo corte',
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 14,
        attentionDays: 30,
        riskDays: 60,
      ),
      appointmentIntervalsDays: [7, 14, 21, 30],
      itemPresets: [
        BusinessItemPreset(
          id: 'haircut',
          name: 'Corte',
          kind: BusinessItemKind.service,
          iconKey: 'cut',
        ),
        BusinessItemPreset(
          id: 'beard',
          name: 'Barba',
          kind: BusinessItemKind.service,
          iconKey: 'cut',
        ),
        BusinessItemPreset(
          id: 'hair_treatment',
          name: 'Tratamento',
          kind: BusinessItemKind.service,
          iconKey: 'spa',
        ),
      ],
    ),
    BusinessProfile(
      id: 'salon',
      label: 'Salao de beleza',
      iconKey: 'salon',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: true,
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 21,
        attentionDays: 45,
        riskDays: 75,
      ),
      itemPresets: [
        BusinessItemPreset(
          id: 'hair_service',
          name: 'Cabelo',
          kind: BusinessItemKind.service,
          iconKey: 'salon',
        ),
        BusinessItemPreset(
          id: 'nails',
          name: 'Unhas',
          kind: BusinessItemKind.service,
          iconKey: 'spa',
        ),
      ],
    ),
    BusinessProfile(
      id: 'spa',
      label: 'Spa e estetica',
      iconKey: 'spa',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: true,
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 30,
        attentionDays: 60,
        riskDays: 90,
      ),
      itemPresets: [
        BusinessItemPreset(
          id: 'massage',
          name: 'Massagem',
          kind: BusinessItemKind.service,
          iconKey: 'spa',
        ),
        BusinessItemPreset(
          id: 'treatment',
          name: 'Tratamento',
          kind: BusinessItemKind.service,
          iconKey: 'spa',
        ),
      ],
    ),
    BusinessProfile(
      id: 'retail',
      label: 'Loja e comercio',
      iconKey: 'store',
      capabilities: BusinessCapabilities(
        services: false,
        products: true,
        appointments: false,
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 30,
        attentionDays: 60,
        riskDays: 120,
      ),
    ),
    BusinessProfile(
      id: 'restaurant',
      label: 'Restaurante',
      iconKey: 'restaurant',
      capabilities: BusinessCapabilities(
        services: false,
        products: true,
        appointments: false,
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 7,
        attentionDays: 21,
        riskDays: 45,
      ),
      itemPresets: [
        BusinessItemPreset(
          id: 'meal',
          name: 'Refeicao',
          kind: BusinessItemKind.product,
          iconKey: 'restaurant',
        ),
        BusinessItemPreset(
          id: 'drink',
          name: 'Bebida',
          kind: BusinessItemKind.product,
          iconKey: 'cafe',
        ),
      ],
    ),
    BusinessProfile(
      id: 'cafe',
      label: 'Cafe e pastelaria',
      iconKey: 'cafe',
      capabilities: BusinessCapabilities(
        services: false,
        products: true,
        appointments: false,
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 7,
        attentionDays: 21,
        riskDays: 45,
      ),
      itemPresets: [
        BusinessItemPreset(
          id: 'coffee',
          name: 'Cafe',
          kind: BusinessItemKind.product,
          iconKey: 'cafe',
        ),
        BusinessItemPreset(
          id: 'pastry',
          name: 'Pastelaria',
          kind: BusinessItemKind.product,
          iconKey: 'cafe',
        ),
      ],
    ),
    BusinessProfile(
      id: 'clinic',
      label: 'Clinica e saude',
      iconKey: 'clinic',
      capabilities: BusinessCapabilities(
        services: true,
        products: false,
        appointments: true,
      ),
      appointmentIntervalsDays: [7, 14, 30, 90],
      itemPresets: [
        BusinessItemPreset(
          id: 'consultation',
          name: 'Consulta',
          kind: BusinessItemKind.service,
          iconKey: 'clinic',
        ),
      ],
    ),
    BusinessProfile(
      id: 'gym',
      label: 'Ginasio e fitness',
      iconKey: 'gym',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: false,
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 7,
        attentionDays: 14,
        riskDays: 30,
      ),
      itemPresets: [
        BusinessItemPreset(
          id: 'membership',
          name: 'Mensalidade',
          kind: BusinessItemKind.service,
          iconKey: 'gym',
        ),
      ],
    ),
    BusinessProfile(
      id: 'workshop',
      label: 'Oficina e reparacoes',
      iconKey: 'workshop',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: true,
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 60,
        attentionDays: 120,
        riskDays: 240,
      ),
      appointmentIntervalsDays: [30, 90, 180],
      itemPresets: [
        BusinessItemPreset(
          id: 'repair',
          name: 'Reparacao',
          kind: BusinessItemKind.service,
          iconKey: 'workshop',
        ),
        BusinessItemPreset(
          id: 'maintenance',
          name: 'Manutencao',
          kind: BusinessItemKind.service,
          iconKey: 'workshop',
        ),
      ],
    ),
    BusinessProfile(
      id: 'professional_services',
      label: 'Servicos profissionais',
      iconKey: 'services',
      capabilities: BusinessCapabilities(
        services: true,
        products: false,
        appointments: true,
      ),
      appointmentIntervalsDays: [7, 14, 30],
      itemPresets: [
        BusinessItemPreset(
          id: 'consulting',
          name: 'Atendimento',
          kind: BusinessItemKind.service,
          iconKey: 'services',
        ),
      ],
    ),
    generic,
  ];

  static BusinessProfile resolve(String? businessType) {
    final normalized = _normalize(businessType);
    if (normalized.isEmpty) return generic;

    for (final profile in all) {
      if (_normalize(profile.id) == normalized ||
          _normalize(profile.label) == normalized) {
        return profile;
      }
    }

    if (normalized.contains('barbear')) return all.first;
    if (normalized.contains('salao') || normalized.contains('beleza')) {
      return all.firstWhere((profile) => profile.id == 'salon');
    }
    if (normalized.contains('loja') || normalized.contains('comerc')) {
      return all.firstWhere((profile) => profile.id == 'retail');
    }
    return generic;
  }

  static BusinessProfile resolveBusinessData(Map<String, dynamic> data) {
    final storedType = (data['business_type'] as String?)?.trim();
    final isLegacyBusiness = (storedType == null || storedType.isEmpty) &&
        data['business_profile_version'] == null;
    return resolve(
      isLegacyBusiness ? 'barbershop' : storedType,
    ).withMerchantOverrides(data);
  }

  static String _normalize(String? value) {
    return (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
