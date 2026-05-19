package com.tsintsivadigital.maisum.config.api.dto;

import com.tsintsivadigital.maisum.config.domain.ConfigType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public class ConfigItemRequest {
  @NotBlank
  private String key;

  @NotNull
  private ConfigType type;

  private boolean enabled = true;

  private String defaultPayload;

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
}
