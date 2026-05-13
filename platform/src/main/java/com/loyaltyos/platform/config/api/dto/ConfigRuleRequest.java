package com.loyaltyos.platform.config.api.dto;

import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import java.util.UUID;

public class ConfigRuleRequest {
  @NotBlank
  private String configKey;

  private UUID segmentId;

  private int priority = 100;

  private int rolloutPct = 100;

  private boolean enabled = true;

  private String payloadOverride;

  private Instant startsAt;

  private Instant endsAt;

  public String getConfigKey() {
    return configKey;
  }

  public void setConfigKey(String configKey) {
    this.configKey = configKey;
  }

  public UUID getSegmentId() {
    return segmentId;
  }

  public void setSegmentId(UUID segmentId) {
    this.segmentId = segmentId;
  }

  public int getPriority() {
    return priority;
  }

  public void setPriority(int priority) {
    this.priority = priority;
  }

  public int getRolloutPct() {
    return rolloutPct;
  }

  public void setRolloutPct(int rolloutPct) {
    this.rolloutPct = rolloutPct;
  }

  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  public String getPayloadOverride() {
    return payloadOverride;
  }

  public void setPayloadOverride(String payloadOverride) {
    this.payloadOverride = payloadOverride;
  }

  public Instant getStartsAt() {
    return startsAt;
  }

  public void setStartsAt(Instant startsAt) {
    this.startsAt = startsAt;
  }

  public Instant getEndsAt() {
    return endsAt;
  }

  public void setEndsAt(Instant endsAt) {
    this.endsAt = endsAt;
  }
}
