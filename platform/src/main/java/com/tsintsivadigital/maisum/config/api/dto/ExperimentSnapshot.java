package com.tsintsivadigital.maisum.config.api.dto;

import java.util.Map;

public class ExperimentSnapshot {
  private final String variant;
  private final Map<String, Object> payload;

  public ExperimentSnapshot(String variant, Map<String, Object> payload) {
    this.variant = variant;
    this.payload = payload;
  }

  public String getVariant() {
    return variant;
  }

  public Map<String, Object> getPayload() {
    return payload;
  }
}
