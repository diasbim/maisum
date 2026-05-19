package com.tsintsivadigital.maisum.config.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "experiment_assignments")
public class ExperimentAssignment {
  @Id
  @Column(columnDefinition = "uuid")
  private UUID id;

  @Column(name = "config_key", nullable = false)
  private String configKey;

  @Column(name = "merchant_id", nullable = false)
  private String merchantId;

  @Column(nullable = false)
  private String variant;

  @Column(name = "assigned_at", nullable = false)
  private Instant assignedAt;

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

  public String getMerchantId() {
    return merchantId;
  }

  public void setMerchantId(String merchantId) {
    this.merchantId = merchantId;
  }

  public String getVariant() {
    return variant;
  }

  public void setVariant(String variant) {
    this.variant = variant;
  }

  public Instant getAssignedAt() {
    return assignedAt;
  }

  public void setAssignedAt(Instant assignedAt) {
    this.assignedAt = assignedAt;
  }
}
