package com.tsintsivadigital.maisum.notifications;

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
