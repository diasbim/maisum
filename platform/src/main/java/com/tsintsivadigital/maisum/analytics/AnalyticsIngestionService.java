package com.tsintsivadigital.maisum.analytics;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsintsivadigital.maisum.analytics.dto.AnalyticsEventRequest;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class AnalyticsIngestionService {
  private final JdbcTemplate jdbcTemplate;
  private final ObjectMapper objectMapper;

  public AnalyticsIngestionService(JdbcTemplate jdbcTemplate, ObjectMapper objectMapper) {
    this.jdbcTemplate = jdbcTemplate;
    this.objectMapper = objectMapper;
  }

  public void ingest(String merchantId, List<AnalyticsEventRequest> events) {
    if (events == null || events.isEmpty()) {
      return;
    }
    String sql = "INSERT INTO analytics_events "
        + "(id, merchant_id, event_type, occurred_at, received_at, source, device_id, app_version, properties) "
        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb)";
    Instant receivedAt = Instant.now();
    jdbcTemplate.batchUpdate(sql, events, events.size(), (ps, event) -> {
      ps.setObject(1, UUID.randomUUID());
      ps.setString(2, merchantId);
      ps.setString(3, event.getEventType());
      ps.setTimestamp(4, Timestamp.from(event.getOccurredAt()));
      ps.setTimestamp(5, Timestamp.from(receivedAt));
      ps.setString(6, event.getSource());
      ps.setString(7, event.getDeviceId());
      ps.setString(8, event.getAppVersion());
      ps.setString(9, toJson(event.getProperties()));
    });
  }

  private String toJson(Object payload) {
    if (payload == null) {
      return null;
    }
    try {
      return objectMapper.writeValueAsString(payload);
    } catch (Exception ex) {
      throw new IllegalArgumentException("Unable to serialize analytics payload", ex);
    }
  }
}
