package com.tsintsivadigital.maisum.config.api.dto;

import jakarta.validation.constraints.NotBlank;

public class ConfigSegmentRequest {
  @NotBlank
  private String name;

  private boolean enabled = true;

  @NotBlank
  private String conditions;

  public String getName() {
    return name;
  }

  public void setName(String name) {
    this.name = name;
  }

  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  public String getConditions() {
    return conditions;
  }

  public void setConditions(String conditions) {
    this.conditions = conditions;
  }
}
