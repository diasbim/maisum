package com.tsintsivadigital.maisum.notifications;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class NotificationService {
  private final JdbcTemplate jdbcTemplate;
  private final ObjectMapper objectMapper;

  public NotificationService(JdbcTemplate jdbcTemplate, ObjectMapper objectMapper) {
    this.jdbcTemplate = jdbcTemplate;
    this.objectMapper = objectMapper;
  }

  public UUID enqueue(String merchantId, NotificationRequest request) {
    UUID id = UUID.randomUUID();
    Instant now = Instant.now();
    Instant scheduledAt = request.getScheduledAt() != null ? request.getScheduledAt() : now;

    String sql = "INSERT INTO notification_queue "
        + "(id, merchant_id, channel, status, payload, scheduled_at, sent_at, retry_count, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?::jsonb, ?, ?, ?, ?, ?)";

    jdbcTemplate.update(
        sql,
        id,
        merchantId,
        request.getChannel(),
        "pending",
        toJson(request.getPayload()),
        Timestamp.from(scheduledAt),
        null,
        0,
        Timestamp.from(now),
        Timestamp.from(now));

    return id;
  }

  private String toJson(Object payload) {
    if (payload == null) {
      return null;
    }
    try {
      return objectMapper.writeValueAsString(payload);
    } catch (Exception ex) {
      throw new IllegalArgumentException("Unable to serialize notification payload", ex);
    }
  }
}
