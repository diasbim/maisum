package com.loyaltyos.platform.notifications;

import java.util.UUID;

public class NotificationResponse {
  private final UUID id;

  public NotificationResponse(UUID id) {
    this.id = id;
  }

  public UUID getId() {
    return id;
  }
}
