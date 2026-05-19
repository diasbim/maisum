package com.tsintsivadigital.maisum.retention;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class RetentionMetricsJob {
  private final JdbcTemplate jdbcTemplate;

  public RetentionMetricsJob(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  @Scheduled(cron = "${platform.jobs.retentionMetricsCron:0 20 1 * * *}")
  public void calculateRetentionMetrics() {
    String sql = """
        WITH previous AS (
          SELECT customer_id, risk_level
          FROM retention_metrics
        ),
        sales_agg AS (
          SELECT
            c.merchant_id,
            c.id AS customer_id,
            MIN(s.created_at) AS first_visit_at,
            MAX(s.created_at) AS last_visit_at,
            COUNT(s.id)::int AS total_visits,
            COALESCE(SUM(s.amount), 0)::numeric(12,2) AS total_spent
          FROM customers c
          LEFT JOIN sales s
            ON s.customer_id = c.id
           AND s.merchant_id = c.merchant_id
          GROUP BY c.merchant_id, c.id
        ),
        computed AS (
          SELECT
            merchant_id,
            customer_id,
            first_visit_at,
            last_visit_at,
            total_visits,
            total_spent,
            CASE
              WHEN last_visit_at IS NULL THEN 999
              ELSE (CURRENT_DATE - DATE(last_visit_at))::int
            END AS days_inactive,
            CASE
              WHEN total_visits <= 1 OR first_visit_at IS NULL OR last_visit_at IS NULL THEN 0
              WHEN DATE(last_visit_at) <= DATE(first_visit_at) THEN 0
              ELSE ROUND(
                (DATE(last_visit_at) - DATE(first_visit_at))::numeric / NULLIF(total_visits - 1, 0)
              )::int
            END AS average_visit_interval
          FROM sales_agg
        ),
        finalized AS (
          SELECT
            merchant_id,
            customer_id,
            last_visit_at,
            total_visits,
            total_spent,
            days_inactive,
            average_visit_interval,
            CASE
              WHEN days_inactive <= 14 THEN 'active'
              WHEN days_inactive <= 29 THEN 'attention'
              WHEN days_inactive <= 59 THEN 'risk'
              ELSE 'lost'
            END AS risk_level,
            (total_visits >= 2) AS is_recurring
          FROM computed
        )
        INSERT INTO retention_metrics (
          id,
          merchant_id,
          customer_id,
          last_visit_at,
          days_inactive,
          risk_level,
          total_visits,
          average_visit_interval,
          total_spent,
          is_recurring,
          recovered,
          updated_at,
          synced
        )
        SELECT
          f.merchant_id || '_' || f.customer_id AS id,
          f.merchant_id,
          f.customer_id,
          f.last_visit_at,
          f.days_inactive,
          f.risk_level,
          f.total_visits,
          f.average_visit_interval,
          f.total_spent,
          f.is_recurring,
          CASE
            WHEN p.risk_level IN ('risk', 'lost')
             AND f.risk_level IN ('active', 'attention') THEN true
            ELSE false
          END AS recovered,
          NOW(),
          true
        FROM finalized f
        LEFT JOIN previous p ON p.customer_id = f.customer_id
        ON CONFLICT (id) DO UPDATE SET
          last_visit_at = EXCLUDED.last_visit_at,
          days_inactive = EXCLUDED.days_inactive,
          risk_level = EXCLUDED.risk_level,
          total_visits = EXCLUDED.total_visits,
          average_visit_interval = EXCLUDED.average_visit_interval,
          total_spent = EXCLUDED.total_spent,
          is_recurring = EXCLUDED.is_recurring,
          recovered = EXCLUDED.recovered,
          updated_at = EXCLUDED.updated_at,
          synced = EXCLUDED.synced
        """;

    jdbcTemplate.update(sql);
  }
}
