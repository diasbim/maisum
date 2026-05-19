package com.tsintsivadigital.maisum.sync.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.time.Instant;
import java.util.Map;

public class SyncMutationRequest {
  @NotBlank
  private String operation;

  @NotNull
  private Map<String, Object> payload;

  @JsonProperty("queued_at")
  private Instant queuedAt;

  public String getOperation() {
    return operation;
  }

  public void setOperation(String operation) {
    this.operation = operation;
  }

  public Map<String, Object> getPayload() {
    return payload;
  }

  public void setPayload(Map<String, Object> payload) {
    this.payload = payload;
  }

  public Instant getQueuedAt() {
    return queuedAt;
  }

  public void setQueuedAt(Instant queuedAt) {
    this.queuedAt = queuedAt;
  }
}
