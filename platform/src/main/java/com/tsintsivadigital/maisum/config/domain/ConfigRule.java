package com.tsintsivadigital.maisum.config.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "config_rules")
public class ConfigRule {
  @Id
  @Column(columnDefinition = "uuid")
  private UUID id;

  @Column(name = "config_key", nullable = false)
  private String configKey;

  @Column(name = "segment_id", columnDefinition = "uuid")
  private UUID segmentId;

  @Column(nullable = false)
  private int priority;

  @Column(name = "rollout_pct", nullable = false)
  private int rolloutPct;

  @Column(name = "is_enabled", nullable = false)
  private boolean enabled;

  @Column(name = "payload_override", columnDefinition = "jsonb")
  private String payloadOverride;

  @Column(name = "starts_at")
  private Instant startsAt;

  @Column(name = "ends_at")
  private Instant endsAt;

  @Column(name = "created_at", nullable = false)
  private Instant createdAt;

  @Column(name = "updated_at", nullable = false)
  private Instant updatedAt;

  public UUID getId() {
    return id;
  }

  public void setId(UUID id) {
    this.id = id;
  }

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

  public Instant getCreatedAt() {
    return createdAt;
  }

  public void setCreatedAt(Instant createdAt) {
    this.createdAt = createdAt;
  }

  public Instant getUpdatedAt() {
    return updatedAt;
  }

  public void setUpdatedAt(Instant updatedAt) {
    this.updatedAt = updatedAt;
  }
}
