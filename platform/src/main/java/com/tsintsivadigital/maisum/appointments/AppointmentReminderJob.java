package com.tsintsivadigital.maisum.appointments;

import com.tsintsivadigital.maisum.notifications.NotificationRequest;
import com.tsintsivadigital.maisum.notifications.NotificationService;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class AppointmentReminderJob {
  private final JdbcTemplate jdbcTemplate;
  private final NotificationService notificationService;

  public AppointmentReminderJob(
      JdbcTemplate jdbcTemplate,
      NotificationService notificationService) {
    this.jdbcTemplate = jdbcTemplate;
    this.notificationService = notificationService;
  }

  @Scheduled(cron = "${platform.jobs.appointmentReminderCron:0 0 8 * * *}")
  public void enqueueDailyReminders() {
    Instant now = Instant.now();
    Instant next24h = now.plusSeconds(24 * 60 * 60);

    String sql = """
        SELECT a.id,
               a.merchant_id,
               a.customer_id,
               a.scheduled_date,
               COALESCE(NULLIF(TRIM(c.name), ''), 'Cliente') AS customer_name
        FROM appointments a
        LEFT JOIN customers c
          ON c.id = a.customer_id AND c.merchant_id = a.merchant_id
        WHERE a.status = 'scheduled'
          AND a.reminder_sent = false
          AND a.scheduled_date >= ?
          AND a.scheduled_date <= ?
        ORDER BY a.merchant_id, a.scheduled_date ASC
        """;

    List<Map<String, Object>> rows = jdbcTemplate.queryForList(
        sql,
        Timestamp.from(now),
        Timestamp.from(next24h));

    for (Map<String, Object> row : rows) {
      String appointmentId = asString(row.get("id"));
      String merchantId = asString(row.get("merchant_id"));
      String customerId = asString(row.get("customer_id"));
      String customerName = asString(row.get("customer_name"));
      Timestamp scheduledDate = (Timestamp) row.get("scheduled_date");

      NotificationRequest request = new NotificationRequest();
      request.setChannel("push");
      request.setScheduledAt(now);
      request.setPayload(buildPayload(
          appointmentId,
          merchantId,
          customerId,
          customerName,
          scheduledDate == null ? null : scheduledDate.toInstant()));

      notificationService.enqueue(merchantId, request);

      jdbcTemplate.update(
          "UPDATE appointments SET reminder_sent = true, updated_at = ? WHERE id = ? AND merchant_id = ?",
          Timestamp.from(now),
          appointmentId,
          merchantId);
    }
  }

  private Map<String, Object> buildPayload(
      String appointmentId,
      String merchantId,
      String customerId,
      String customerName,
      Instant scheduledDate) {
    Map<String, Object> payload = new HashMap<>();
    payload.put("type", "appointment_reminder");
    payload.put("title", "Lembrete de agendamento");
    payload.put("body", customerName + " tem corte agendado para hoje");
    payload.put("appointment_id", appointmentId);
    payload.put("merchant_id", merchantId);
    payload.put("customer_id", customerId);
    payload.put("scheduled_date", scheduledDate == null ? null : scheduledDate.toEpochMilli());
    return payload;
  }

  private String asString(Object value) {
    if (value == null) {
      return "";
    }
    return String.valueOf(value);
  }
}
