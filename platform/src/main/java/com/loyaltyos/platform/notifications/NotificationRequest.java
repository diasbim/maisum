package com.loyaltyos.platform.notifications;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import java.util.Map;

public class NotificationRequest {
  @NotBlank
  private String channel;

  private Map<String, Object> payload;

  @JsonProperty("scheduled_at")
  private Instant scheduledAt;

  public String getChannel() {
    return channel;
  }

  public void setChannel(String channel) {
    this.channel = channel;
  }

  public Map<String, Object> getPayload() {
    return payload;
  }

  public void setPayload(Map<String, Object> payload) {
    this.payload = payload;
  }

  public Instant getScheduledAt() {
    return scheduledAt;
  }

  public void setScheduledAt(Instant scheduledAt) {
    this.scheduledAt = scheduledAt;
  }
}
