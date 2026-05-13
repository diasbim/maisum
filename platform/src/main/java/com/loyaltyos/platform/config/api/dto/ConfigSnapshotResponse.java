package com.loyaltyos.platform.config.api.dto;

import java.time.Instant;
import java.util.Map;

public class ConfigSnapshotResponse {
  private final Instant generatedAt;
  private final Map<String, Boolean> flags;
  private final Map<String, Object> configs;
  private final Map<String, ExperimentSnapshot> experiments;

  public ConfigSnapshotResponse(
      Instant generatedAt,
      Map<String, Boolean> flags,
      Map<String, Object> configs,
      Map<String, ExperimentSnapshot> experiments) {
    this.generatedAt = generatedAt;
    this.flags = flags;
    this.configs = configs;
    this.experiments = experiments;
  }

  public Instant getGeneratedAt() {
    return generatedAt;
  }

  public Map<String, Boolean> getFlags() {
    return flags;
  }

  public Map<String, Object> getConfigs() {
    return configs;
  }

  public Map<String, ExperimentSnapshot> getExperiments() {
    return experiments;
  }
}
