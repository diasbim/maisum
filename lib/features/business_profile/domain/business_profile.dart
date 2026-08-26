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
    this.business = 'negócio',
    this.businessCode = 'Código do negócio',
    this.transaction = 'venda',
    this.appointment = 'marcação',
    this.appointments = 'marcações',
    this.nextVisit = 'próxima visita',
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
    label: 'Outro negócio local',
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
        nextVisit: 'próximo corte',
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
      label: 'Salão de beleza',
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
      label: 'Spa e estética',
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
      label: 'Loja e comércio',
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
          name: 'Refeição',
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
      label: 'Café e pastelaria',
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
      id: 'car_wash',
      label: 'Lavagem Automóvel',
      iconKey: 'car_wash',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: true,
      ),
      terminology: BusinessTerminology(
        appointment: 'lavagem',
        appointments: 'lavagens',
        nextVisit: 'próxima lavagem',
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 14,
        attentionDays: 30,
        riskDays: 60,
      ),
      appointmentIntervalsDays: [7, 14, 30, 60],
      itemPresets: [
        BusinessItemPreset(
          id: 'basic_wash',
          name: 'Lavagem simples',
          kind: BusinessItemKind.service,
          iconKey: 'car_wash',
        ),
        BusinessItemPreset(
          id: 'interior_cleaning',
          name: 'Limpeza interior',
          kind: BusinessItemKind.service,
          iconKey: 'car_wash',
        ),
        BusinessItemPreset(
          id: 'polishing',
          name: 'Polimento',
          kind: BusinessItemKind.service,
          iconKey: 'car_wash',
        ),
        BusinessItemPreset(
          id: 'air_freshener',
          name: 'Ambientador',
          kind: BusinessItemKind.product,
          iconKey: 'car_wash',
        ),
      ],
    ),
    BusinessProfile(
      id: 'laundry',
      label: 'Lavandaria',
      iconKey: 'laundry',
      capabilities: BusinessCapabilities(
        services: true,
        products: false,
        appointments: true,
      ),
      terminology: BusinessTerminology(
        appointment: 'recolha',
        appointments: 'recolhas',
        nextVisit: 'próxima recolha',
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 14,
        attentionDays: 30,
        riskDays: 60,
      ),
      appointmentIntervalsDays: [7, 14, 30],
      itemPresets: [
        BusinessItemPreset(
          id: 'wash_and_fold',
          name: 'Lavar e dobrar',
          kind: BusinessItemKind.service,
          iconKey: 'laundry',
        ),
        BusinessItemPreset(
          id: 'dry_cleaning',
          name: 'Limpeza a seco',
          kind: BusinessItemKind.service,
          iconKey: 'laundry',
        ),
        BusinessItemPreset(
          id: 'ironing',
          name: 'Engomadoria',
          kind: BusinessItemKind.service,
          iconKey: 'laundry',
        ),
      ],
    ),
    BusinessProfile(
      id: 'bakery',
      label: 'Padaria',
      iconKey: 'bakery',
      capabilities: BusinessCapabilities(
        services: false,
        products: true,
        appointments: false,
      ),
      terminology: BusinessTerminology(
        transaction: 'compra',
        nextVisit: 'próxima compra',
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 7,
        attentionDays: 14,
        riskDays: 30,
      ),
      itemPresets: [
        BusinessItemPreset(
          id: 'bread',
          name: 'Pão',
          kind: BusinessItemKind.product,
          iconKey: 'bakery',
        ),
        BusinessItemPreset(
          id: 'cake',
          name: 'Bolo',
          kind: BusinessItemKind.product,
          iconKey: 'bakery',
        ),
        BusinessItemPreset(
          id: 'pastry',
          name: 'Pastel',
          kind: BusinessItemKind.product,
          iconKey: 'bakery',
        ),
      ],
    ),
    BusinessProfile(
      id: 'pharmacy',
      label: 'Farmácia',
      iconKey: 'pharmacy',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: false,
      ),
      terminology: BusinessTerminology(
        transaction: 'compra',
        nextVisit: 'próxima compra',
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 21,
        attentionDays: 45,
        riskDays: 90,
      ),
      itemPresets: [
        BusinessItemPreset(
          id: 'medicine',
          name: 'Medicamento',
          kind: BusinessItemKind.product,
          iconKey: 'pharmacy',
        ),
        BusinessItemPreset(
          id: 'health_product',
          name: 'Produto de saúde',
          kind: BusinessItemKind.product,
          iconKey: 'pharmacy',
        ),
        BusinessItemPreset(
          id: 'basic_care',
          name: 'Atendimento básico',
          kind: BusinessItemKind.service,
          iconKey: 'pharmacy',
        ),
      ],
    ),
    BusinessProfile(
      id: 'pet_care',
      label: 'Pet care',
      iconKey: 'pet_care',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: true,
      ),
      terminology: BusinessTerminology(
        business: 'serviço pet',
        appointment: 'agendamento',
        appointments: 'agendamentos',
        nextVisit: 'próximo cuidado',
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 30,
        attentionDays: 60,
        riskDays: 120,
      ),
      appointmentIntervalsDays: [14, 30, 60, 90],
      itemPresets: [
        BusinessItemPreset(
          id: 'pet_bath',
          name: 'Banho',
          kind: BusinessItemKind.service,
          iconKey: 'pet_care',
        ),
        BusinessItemPreset(
          id: 'grooming',
          name: 'Tosa',
          kind: BusinessItemKind.service,
          iconKey: 'pet_care',
        ),
        BusinessItemPreset(
          id: 'pet_food',
          name: 'Ração',
          kind: BusinessItemKind.product,
          iconKey: 'pet_care',
        ),
      ],
    ),
    BusinessProfile(
      id: 'tailoring',
      label: 'Alfaiataria',
      iconKey: 'tailoring',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: true,
      ),
      terminology: BusinessTerminology(
        appointment: 'prova',
        appointments: 'provas',
        nextVisit: 'próxima prova',
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 30,
        attentionDays: 90,
        riskDays: 180,
      ),
      appointmentIntervalsDays: [7, 14, 30, 90],
      itemPresets: [
        BusinessItemPreset(
          id: 'adjustment',
          name: 'Ajuste',
          kind: BusinessItemKind.service,
          iconKey: 'tailoring',
        ),
        BusinessItemPreset(
          id: 'custom_clothing',
          name: 'Peça sob medida',
          kind: BusinessItemKind.product,
          iconKey: 'tailoring',
        ),
        BusinessItemPreset(
          id: 'clothing_repair',
          name: 'Reparação de roupa',
          kind: BusinessItemKind.service,
          iconKey: 'tailoring',
        ),
      ],
    ),
    BusinessProfile(
      id: 'phone_repair',
      label: 'Reparação de Telemóveis',
      iconKey: 'phone_repair',
      capabilities: BusinessCapabilities(
        services: true,
        products: true,
        appointments: true,
      ),
      terminology: BusinessTerminology(
        appointment: 'reparação',
        appointments: 'reparações',
        nextVisit: 'próxima assistência',
      ),
      retention: BusinessRetentionDefaults(
        activeDays: 60,
        attentionDays: 120,
        riskDays: 240,
      ),
      appointmentIntervalsDays: [7, 30, 90, 180],
      itemPresets: [
        BusinessItemPreset(
          id: 'screen_replacement',
          name: 'Troca de ecrã',
          kind: BusinessItemKind.service,
          iconKey: 'phone_repair',
        ),
        BusinessItemPreset(
          id: 'battery_replacement',
          name: 'Troca de bateria',
          kind: BusinessItemKind.service,
          iconKey: 'phone_repair',
        ),
        BusinessItemPreset(
          id: 'phone_accessory',
          name: 'Acessório',
          kind: BusinessItemKind.product,
          iconKey: 'phone_repair',
        ),
      ],
    ),
    BusinessProfile(
      id: 'clinic',
      label: 'Clínica e saúde',
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
      label: 'Oficina e reparações',
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
          name: 'Reparação',
          kind: BusinessItemKind.service,
          iconKey: 'workshop',
        ),
        BusinessItemPreset(
          id: 'maintenance',
          name: 'Manutenção',
          kind: BusinessItemKind.service,
          iconKey: 'workshop',
        ),
      ],
    ),
    BusinessProfile(
      id: 'professional_services',
      label: 'Serviços profissionais',
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

  static const _profileAliases = <String, String>{
    'barber': 'barbershop',
    'barber_shop': 'barbershop',
    'barbear': 'barbershop',
    'barbearia': 'barbershop',
    'salao': 'salon',
    'salao_de_beleza': 'salon',
    'beauty_salon': 'salon',
    'loja': 'retail',
    'comercio': 'retail',
    'retalho': 'retail',
    'shop': 'retail',
    'carwash': 'car_wash',
    'auto_wash': 'car_wash',
    'lavacar': 'car_wash',
    'lava_car': 'car_wash',
    'lava_jato': 'car_wash',
    'lavagem_auto': 'car_wash',
    'lavagem_de_carros': 'car_wash',
    'lavagem_automovel': 'car_wash',
    'lavagem_automoveis': 'car_wash',
    'lavandaria': 'laundry',
    'lavanderia': 'laundry',
    'limpeza_a_seco': 'laundry',
    'dry_cleaning': 'laundry',
    'padaria': 'bakery',
    'panificadora': 'bakery',
    'bakery_shop': 'bakery',
    'farmacia': 'pharmacy',
    'drogaria': 'pharmacy',
    'drugstore': 'pharmacy',
    'cuidados_de_animais': 'pet_care',
    'cuidados_para_animais': 'pet_care',
    'pet_shop': 'pet_care',
    'pets': 'pet_care',
    'alfaiate': 'tailoring',
    'alfaiataria': 'tailoring',
    'costura': 'tailoring',
    'costureira': 'tailoring',
    'tailor': 'tailoring',
    'reparacao_de_telemoveis': 'phone_repair',
    'telemoveis': 'phone_repair',
    'reparacao_de_celulares': 'phone_repair',
    'conserto_de_celular': 'phone_repair',
    'cell_phone_repair': 'phone_repair',
    'mobile_repair': 'phone_repair',
    'smartphone_repair': 'phone_repair',
  };

  static BusinessProfile resolve(String? businessType) {
    final normalized = _normalize(businessType);
    if (normalized.isEmpty) return generic;

    for (final profile in all) {
      if (_normalize(profile.id) == normalized ||
          _normalize(profile.label) == normalized) {
        return profile;
      }
    }

    final aliasId = _profileAliases[normalized];
    if (aliasId != null) return _byId(aliasId);

    if (_containsAny(normalized, ['barbear', 'barber'])) {
      return _byId('barbershop');
    }
    if (_containsAny(normalized, ['salao', 'beleza', 'beauty_salon'])) {
      return _byId('salon');
    }
    if (_containsAny(normalized, ['loja', 'comerc', 'retalho'])) {
      return _byId('retail');
    }
    if (_containsAny(normalized, ['lavacar']) ||
        (normalized.contains('lava') &&
            _containsAny(normalized, ['car', 'auto', 'jato'])) ||
        (normalized.contains('lavagem') &&
            _containsAny(normalized, ['carro', 'automovel', 'auto']))) {
      return _byId('car_wash');
    }
    if (_containsAny(
      normalized,
      ['lavand', 'laundry', 'limpeza_a_seco', 'dry_clean'],
    )) {
      return _byId('laundry');
    }
    if (_containsAny(normalized, ['padar', 'bakery', 'panificador'])) {
      return _byId('bakery');
    }
    if (_containsAny(normalized, ['farmac', 'pharmacy', 'drogaria'])) {
      return _byId('pharmacy');
    }
    if (_containsAny(normalized, ['pet', 'animais'])) {
      return _byId('pet_care');
    }
    if (_containsAny(normalized, ['alfaiat', 'costur', 'tailor'])) {
      return _byId('tailoring');
    }
    if (_containsAny(normalized, ['telemov', 'celular', 'smartphone']) ||
        (normalized.contains('phone') && normalized.contains('repair'))) {
      return _byId('phone_repair');
    }

    return generic;
  }

  static BusinessProfile _byId(String id) {
    return all.firstWhere((profile) => profile.id == id);
  }

  static bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
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
    final normalized = (value ?? '').trim().toLowerCase();
    return normalized
        .replaceAll(RegExp('[áàâãä]'), 'a')
        .replaceAll(RegExp('[éèêë]'), 'e')
        .replaceAll(RegExp('[íìîï]'), 'i')
        .replaceAll(RegExp('[óòôõö]'), 'o')
        .replaceAll(RegExp('[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }
}
