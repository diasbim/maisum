package com.tsintsivadigital.maisum.appointments;

import static org.junit.jupiter.api.Assertions.assertEquals;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsintsivadigital.maisum.notifications.NotificationService;
import java.sql.Timestamp;
import java.time.Instant;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class AppointmentReminderJobIntegrationTest {

  @Container
  static final PostgreSQLContainer<?> POSTGRES =
      new PostgreSQLContainer<>("postgres:16-alpine")
          .withDatabaseName("loyaltyos_test")
          .withUsername("test")
          .withPassword("test");

  private JdbcTemplate jdbcTemplate;
  private AppointmentReminderJob job;

  @BeforeEach
  void setUp() {
    DriverManagerDataSource dataSource = new DriverManagerDataSource();
    dataSource.setDriverClassName(POSTGRES.getDriverClassName());
    dataSource.setUrl(POSTGRES.getJdbcUrl());
    dataSource.setUsername(POSTGRES.getUsername());
    dataSource.setPassword(POSTGRES.getPassword());

    jdbcTemplate = new JdbcTemplate(dataSource);
    NotificationService notificationService =
        new NotificationService(jdbcTemplate, new ObjectMapper());
    job = new AppointmentReminderJob(jdbcTemplate, notificationService);

    createSchema();
  }

  @AfterEach
  void cleanUp() {
    jdbcTemplate.execute("DROP TABLE IF EXISTS notification_queue");
    jdbcTemplate.execute("DROP TABLE IF EXISTS appointments");
    jdbcTemplate.execute("DROP TABLE IF EXISTS customers");
  }

  @Test
  void enqueueDailyReminders_enqueuesOnlyEligibleAppointments() {
    Instant now = Instant.now();

    jdbcTemplate.update(
        "INSERT INTO customers (id, merchant_id, name) VALUES (?, ?, ?)",
        "customer-1",
        "merchant-1",
        "Carlos");

    jdbcTemplate.update(
        """
          INSERT INTO appointments
            (id, merchant_id, customer_id, scheduled_date, status, source,
             reminder_sent, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        "appt-due",
        "merchant-1",
        "customer-1",
        Timestamp.from(now.plusSeconds(2 * 60 * 60)),
        "scheduled",
        "post_sale_flow",
        false,
        Timestamp.from(now),
        Timestamp.from(now));

    jdbcTemplate.update(
        """
          INSERT INTO appointments
            (id, merchant_id, customer_id, scheduled_date, status, source,
             reminder_sent, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        "appt-later",
        "merchant-1",
        "customer-1",
        Timestamp.from(now.plusSeconds(30 * 60 * 60)),
        "scheduled",
        "post_sale_flow",
        false,
        Timestamp.from(now),
        Timestamp.from(now));

    jdbcTemplate.update(
        """
          INSERT INTO appointments
            (id, merchant_id, customer_id, scheduled_date, status, source,
             reminder_sent, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        "appt-already-reminded",
        "merchant-1",
        "customer-1",
        Timestamp.from(now.plusSeconds(2 * 60 * 60)),
        "scheduled",
        "post_sale_flow",
        true,
        Timestamp.from(now),
        Timestamp.from(now));

    job.enqueueDailyReminders();

    Integer queued =
        jdbcTemplate.queryForObject("SELECT COUNT(*) FROM notification_queue", Integer.class);
    assertEquals(1, queued);

    Boolean dueReminded =
        jdbcTemplate.queryForObject(
            "SELECT reminder_sent FROM appointments WHERE id = ?",
            Boolean.class,
            "appt-due");
    Boolean laterReminded =
        jdbcTemplate.queryForObject(
            "SELECT reminder_sent FROM appointments WHERE id = ?",
            Boolean.class,
            "appt-later");

    assertEquals(true, dueReminded);
    assertEquals(false, laterReminded);
  }

  private void createSchema() {
    jdbcTemplate.execute(
        """
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            merchant_id TEXT NOT NULL,
            name TEXT
          )
        """);

    jdbcTemplate.execute(
        """
          CREATE TABLE appointments (
            id TEXT PRIMARY KEY,
            merchant_id TEXT NOT NULL,
            customer_id TEXT NOT NULL,
            scheduled_date TIMESTAMPTZ NOT NULL,
            status TEXT NOT NULL,
            source TEXT NOT NULL,
            reminder_sent BOOLEAN NOT NULL DEFAULT FALSE,
            created_at TIMESTAMPTZ NOT NULL,
            updated_at TIMESTAMPTZ NOT NULL
          )
        """);

    jdbcTemplate.execute(
        """
          CREATE TABLE notification_queue (
            id UUID PRIMARY KEY,
            merchant_id TEXT NOT NULL,
            channel TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            payload JSONB,
            scheduled_at TIMESTAMPTZ,
            sent_at TIMESTAMPTZ,
            retry_count INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMPTZ NOT NULL,
            updated_at TIMESTAMPTZ NOT NULL
          )
        """);
  }
}
