package com.loyaltyos.platform.config.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "config_items")
public class ConfigItem {
  @Id
  @Column(columnDefinition = "uuid")
  private UUID id;

  @Column(name = "config_key", nullable = false)
  private String key;

  @Enumerated(EnumType.STRING)
  @Column(name = "config_type", nullable = false)
  private ConfigType type;

  @Column(name = "is_enabled", nullable = false)
  private boolean enabled;

  @Column(name = "default_payload", columnDefinition = "jsonb")
  private String defaultPayload;

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

  public String getKey() {
    return key;
  }

  public void setKey(String key) {
    this.key = key;
  }

  public ConfigType getType() {
    return type;
  }

  public void setType(ConfigType type) {
    this.type = type;
  }

  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  public String getDefaultPayload() {
    return defaultPayload;
  }

  public void setDefaultPayload(String defaultPayload) {
    this.defaultPayload = defaultPayload;
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
