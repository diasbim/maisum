package com.loyaltyos.platform.config.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.loyaltyos.platform.common.MerchantContext;
import com.loyaltyos.platform.config.api.dto.ConfigSnapshotResponse;
import com.loyaltyos.platform.config.api.dto.ExperimentSnapshot;
import com.loyaltyos.platform.config.domain.ConfigItem;
import com.loyaltyos.platform.config.domain.ConfigRule;
import com.loyaltyos.platform.config.domain.ConfigSegment;
import com.loyaltyos.platform.config.domain.ConfigType;
import com.loyaltyos.platform.config.repo.ConfigItemRepository;
import com.loyaltyos.platform.config.repo.ConfigRuleRepository;
import com.loyaltyos.platform.config.repo.ConfigSegmentRepository;
import java.io.IOException;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import org.springframework.stereotype.Service;

@Service
public class ConfigEvaluationService {
  private final ConfigItemRepository itemRepository;
  private final ConfigRuleRepository ruleRepository;
  private final ConfigSegmentRepository segmentRepository;
  private final SegmentMatcher segmentMatcher;
  private final RolloutEngine rolloutEngine;
  private final ExperimentAssignmentService assignmentService;
  private final ObjectMapper objectMapper;

  public ConfigEvaluationService(
      ConfigItemRepository itemRepository,
      ConfigRuleRepository ruleRepository,
      ConfigSegmentRepository segmentRepository,
      SegmentMatcher segmentMatcher,
      RolloutEngine rolloutEngine,
      ExperimentAssignmentService assignmentService,
      ObjectMapper objectMapper) {
    this.itemRepository = itemRepository;
    this.ruleRepository = ruleRepository;
    this.segmentRepository = segmentRepository;
    this.segmentMatcher = segmentMatcher;
    this.rolloutEngine = rolloutEngine;
    this.assignmentService = assignmentService;
    this.objectMapper = objectMapper;
  }

  public ConfigSnapshotResponse evaluate(MerchantContext context) {
    Map<String, Boolean> flags = new HashMap<>();
    Map<String, Object> configs = new HashMap<>();
    Map<String, ExperimentSnapshot> experiments = new HashMap<>();

    Map<UUID, ConfigSegment> segments = new HashMap<>();
    for (ConfigSegment segment : segmentRepository.findAll()) {
      segments.put(segment.getId(), segment);
    }

    for (ConfigItem item : itemRepository.findAll()) {
      List<ConfigRule> rules = ruleRepository.findByConfigKeyOrderByPriorityAsc(item.getKey());
      ConfigRule matched = findMatchingRule(item.getKey(), rules, segments, context);

      Map<String, Object> basePayload = parsePayload(item.getDefaultPayload());
      Map<String, Object> overridePayload = matched == null ? null : parsePayload(matched.getPayloadOverride());

      if (item.getType() == ConfigType.FLAG) {
        boolean enabled = item.isEnabled();
        if (overridePayload != null && overridePayload.containsKey("enabled")) {
          enabled = Boolean.parseBoolean(Objects.toString(overridePayload.get("enabled")));
        }
        flags.put(item.getKey(), enabled);
        continue;
      }

      if (overridePayload != null) {
        mergePayload(basePayload, overridePayload);
      }

      if (item.getType() == ConfigType.CONFIG) {
        configs.put(item.getKey(), basePayload);
      } else if (item.getType() == ConfigType.EXPERIMENT) {
        String variant = "control";
        if (overridePayload != null && overridePayload.containsKey("variant")) {
          variant = Objects.toString(overridePayload.get("variant"));
        }
        if (context.getMerchantId() != null) {
          variant = assignmentService.getOrAssign(item.getKey(), context.getMerchantId(), variant);
        }
        experiments.put(item.getKey(), new ExperimentSnapshot(variant, basePayload));
      }
    }

    return new ConfigSnapshotResponse(Instant.now(), flags, configs, experiments);
  }

  private ConfigRule findMatchingRule(
      String configKey,
      List<ConfigRule> rules,
      Map<UUID, ConfigSegment> segments,
      MerchantContext context) {
    String seedBase = context.getMerchantId();
    if (seedBase == null || seedBase.isBlank()) {
      seedBase = context.getDeviceId();
    }
    for (ConfigRule rule : rules) {
      if (!rule.isEnabled() || !isWithinWindow(rule)) {
        continue;
      }
      ConfigSegment segment = rule.getSegmentId() == null ? null : segments.get(rule.getSegmentId());
      if (segment != null && !segmentMatcher.matches(segment, context)) {
        continue;
      }
      if (seedBase != null) {
        String seed = seedBase + ":" + configKey + ":" + rule.getId();
        if (!rolloutEngine.isInRollout(seed, rule.getRolloutPct())) {
          continue;
        }
      }
      return rule;
    }
    return null;
  }

  private boolean isWithinWindow(ConfigRule rule) {
    Instant now = Instant.now();
    if (rule.getStartsAt() != null && now.isBefore(rule.getStartsAt())) {
      return false;
    }
    if (rule.getEndsAt() != null && now.isAfter(rule.getEndsAt())) {
      return false;
    }
    return true;
  }

  private Map<String, Object> parsePayload(String payload) {
    if (payload == null || payload.isBlank()) {
      return new HashMap<>();
    }
    try {
      return objectMapper.readValue(payload, new TypeReference<Map<String, Object>>() {});
    } catch (IOException ex) {
      throw new IllegalArgumentException("Invalid config payload", ex);
    }
  }

  private void mergePayload(Map<String, Object> base, Map<String, Object> overrides) {
    for (Map.Entry<String, Object> entry : overrides.entrySet()) {
      if (entry.getValue() instanceof Map<?, ?> mapValue
          && base.get(entry.getKey()) instanceof Map<?, ?> baseValue) {
        Map<String, Object> merged = new HashMap<>((Map<String, Object>) baseValue);
        merged.putAll((Map<String, Object>) mapValue);
        base.put(entry.getKey(), merged);
      } else {
        base.put(entry.getKey(), entry.getValue());
      }
    }
  }
}
