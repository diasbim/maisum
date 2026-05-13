package com.loyaltyos.platform.config.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.loyaltyos.platform.common.MerchantContext;
import com.loyaltyos.platform.config.domain.ConfigSegment;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Component;

@Component
public class SegmentMatcher {
  private final ObjectMapper objectMapper;

  public SegmentMatcher(ObjectMapper objectMapper) {
    this.objectMapper = objectMapper;
  }

  public boolean matches(ConfigSegment segment, MerchantContext context) {
    if (segment == null || !segment.isEnabled()) {
      return false;
    }
    Map<String, Object> conditions = parseConditions(segment.getConditions());
    for (Map.Entry<String, Object> entry : conditions.entrySet()) {
      if (!matchesCondition(entry.getKey(), entry.getValue(), context)) {
        return false;
      }
    }
    return true;
  }

  private Map<String, Object> parseConditions(String raw) {
    if (raw == null || raw.isBlank()) {
      return Map.of();
    }
    try {
      return objectMapper.readValue(raw, new TypeReference<Map<String, Object>>() {});
    } catch (IOException ex) {
      throw new IllegalArgumentException("Invalid segment conditions JSON", ex);
    }
  }

  private boolean matchesCondition(String key, Object condition, MerchantContext context) {
    String actual = resolveValue(key, context);
    if (actual == null) {
      return false;
    }
    if (condition instanceof Map<?, ?> map) {
      Object eq = map.get("eq");
      if (eq != null && !actual.equals(eq.toString())) {
        return false;
      }
      Object prefix = map.get("prefix");
      if (prefix != null && !actual.startsWith(prefix.toString())) {
        return false;
      }
      Object in = map.get("in");
      if (in instanceof List<?> list && !list.contains(actual)) {
        return false;
      }
      Object notIn = map.get("notIn");
      if (notIn instanceof List<?> list && list.contains(actual)) {
        return false;
      }
      return true;
    }
    return actual.equals(condition.toString());
  }

  private String resolveValue(String key, MerchantContext context) {
    return switch (key) {
      case "merchantId" -> context.getMerchantId();
      case "plan" -> context.getPlan();
      case "region" -> context.getRegion();
      case "appVersion" -> context.getAppVersion();
      case "deviceId" -> context.getDeviceId();
      default -> context.getAttributes().get(key);
    };
  }
}
