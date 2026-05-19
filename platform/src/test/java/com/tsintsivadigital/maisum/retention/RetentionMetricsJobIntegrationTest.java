package com.tsintsivadigital.maisum.retention;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
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
class RetentionMetricsJobIntegrationTest {

  @Container
  static final PostgreSQLContainer<?> POSTGRES =
      new PostgreSQLContainer<>("postgres:16-alpine")
          .withDatabaseName("loyaltyos_test")
          .withUsername("test")
          .withPassword("test");

  private JdbcTemplate jdbcTemplate;
  private RetentionMetricsJob job;

  @BeforeEach
  void setUp() {
    DriverManagerDataSource dataSource = new DriverManagerDataSource();
    dataSource.setDriverClassName(POSTGRES.getDriverClassName());
    dataSource.setUrl(POSTGRES.getJdbcUrl());
    dataSource.setUsername(POSTGRES.getUsername());
    dataSource.setPassword(POSTGRES.getPassword());

    jdbcTemplate = new JdbcTemplate(dataSource);
    job = new RetentionMetricsJob(jdbcTemplate);

    createSchema();
  }

  @AfterEach
  void cleanUp() {
    jdbcTemplate.execute("DROP TABLE IF EXISTS retention_metrics");
    jdbcTemplate.execute("DROP TABLE IF EXISTS sales");
    jdbcTemplate.execute("DROP TABLE IF EXISTS customers");
  }

  @Test
  void calculateRetentionMetrics_updatesRiskBandsAndRecoveredFlag() {
    Instant now = Instant.now();

    jdbcTemplate.update(
        "INSERT INTO customers (id, merchant_id, name, phone, total_points, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        "customer-a",
        "merchant-1",
        "Ana",
        "840000001",
        0,
        Timestamp.from(now),
        Timestamp.from(now));

    jdbcTemplate.update(
        "INSERT INTO customers (id, merchant_id, name, phone, total_points, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        "customer-b",
        "merchant-1",
        "Bruno",
        "840000002",
        0,
        Timestamp.from(now),
        Timestamp.from(now));

    jdbcTemplate.update(
        "INSERT INTO sales (id, merchant_id, customer_id, amount, points, created_at, device_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
        "sale-a-1",
        "merchant-1",
        "customer-a",
        200,
        2,
        Timestamp.from(now.minus(20, ChronoUnit.DAYS)),
        "device-1");

    jdbcTemplate.update(
        "INSERT INTO sales (id, merchant_id, customer_id, amount, points, created_at, device_id) VALUES (?, ?, ?, ?, ?, ?, ?)",
        "sale-a-2",
        "merchant-1",
        "customer-a",
        300,
        3,
        Timestamp.from(now.minus(2, ChronoUnit.DAYS)),
        "device-1");

    jdbcTemplate.update(
        """
          INSERT INTO retention_metrics
            (id, merchant_id, customer_id, last_visit_at, days_inactive, risk_level,
             total_visits, average_visit_interval, total_spent, is_recurring,
             recovered, updated_at, synced)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        "merchant-1_customer-a",
        "merchant-1",
        "customer-a",
        Timestamp.from(now.minus(70, ChronoUnit.DAYS)),
        70,
        "lost",
        1,
        0,
        100,
        false,
        false,
        Timestamp.from(now.minus(70, ChronoUnit.DAYS)),
        true);

    job.calculateRetentionMetrics();

    String riskA =
        jdbcTemplate.queryForObject(
            "SELECT risk_level FROM retention_metrics WHERE id = ?",
            String.class,
            "merchant-1_customer-a");
    Boolean recoveredA =
        jdbcTemplate.queryForObject(
            "SELECT recovered FROM retention_metrics WHERE id = ?",
            Boolean.class,
            "merchant-1_customer-a");
    Integer totalVisitsA =
        jdbcTemplate.queryForObject(
            "SELECT total_visits FROM retention_metrics WHERE id = ?",
            Integer.class,
            "merchant-1_customer-a");

    assertEquals("active", riskA);
    assertEquals(true, recoveredA);
    assertEquals(2, totalVisitsA);

    String riskB =
        jdbcTemplate.queryForObject(
            "SELECT risk_level FROM retention_metrics WHERE id = ?",
            String.class,
            "merchant-1_customer-b");
    Integer daysInactiveB =
        jdbcTemplate.queryForObject(
            "SELECT days_inactive FROM retention_metrics WHERE id = ?",
            Integer.class,
            "merchant-1_customer-b");

    assertEquals("lost", riskB);
    assertTrue(daysInactiveB >= 60);
  }

  private void createSchema() {
    jdbcTemplate.execute(
        """
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            merchant_id TEXT NOT NULL,
            name TEXT NOT NULL,
            phone TEXT NOT NULL,
            total_points INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMPTZ NOT NULL,
            updated_at TIMESTAMPTZ NOT NULL
          )
        """);

    jdbcTemplate.execute(
        """
          CREATE TABLE sales (
            id TEXT PRIMARY KEY,
            merchant_id TEXT NOT NULL,
            customer_id TEXT NOT NULL,
            amount NUMERIC(12, 2) NOT NULL,
            points INTEGER NOT NULL,
            created_at TIMESTAMPTZ NOT NULL,
            device_id TEXT
          )
        """);

    jdbcTemplate.execute(
        """
          CREATE TABLE retention_metrics (
            id TEXT PRIMARY KEY,
            merchant_id TEXT NOT NULL,
            customer_id TEXT NOT NULL,
            last_visit_at TIMESTAMPTZ,
            days_inactive INTEGER NOT NULL DEFAULT 0,
            risk_level TEXT NOT NULL,
            total_visits INTEGER NOT NULL DEFAULT 0,
            average_visit_interval INTEGER NOT NULL DEFAULT 0,
            total_spent NUMERIC(12,2) NOT NULL DEFAULT 0,
            is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
            recovered BOOLEAN NOT NULL DEFAULT FALSE,
            updated_at TIMESTAMPTZ NOT NULL,
            synced BOOLEAN NOT NULL DEFAULT TRUE
          )
        """);
  }
}
