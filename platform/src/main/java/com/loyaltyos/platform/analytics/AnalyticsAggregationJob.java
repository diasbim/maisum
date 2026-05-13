package com.loyaltyos.platform.analytics;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class AnalyticsAggregationJob {
  private final JdbcTemplate jdbcTemplate;

  public AnalyticsAggregationJob(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  @Scheduled(cron = "0 15 2 * * *")
  public void aggregateDailyKpis() {
    String sql = """
        WITH daily AS (
          SELECT merchant_id,
                 date_trunc('day', occurred_at)::date AS day,
                 COUNT(*) FILTER (WHERE event_type = 'sale_registered') AS sales_count,
                 COUNT(*) FILTER (WHERE event_type = 'customer_repeat') AS repeat_customers,
                 COUNT(*) FILTER (WHERE event_type = 'whatsapp_message_sent') AS whatsapp_usage,
                 BOOL_OR(event_type IN ('subscription_activated', 'subscription_renewed')) AS paid_conversion
          FROM analytics_events
          WHERE occurred_at >= (CURRENT_DATE - INTERVAL '30 days')
          GROUP BY merchant_id, day
        ),
        feature_usage AS (
          SELECT merchant_id,
                 date_trunc('day', occurred_at)::date AS day,
                 COALESCE(properties->>'featureKey', properties->>'feature') AS feature_key,
                 COUNT(*) AS usage_count
          FROM analytics_events
          WHERE event_type = 'feature_used'
            AND occurred_at >= (CURRENT_DATE - INTERVAL '30 days')
            AND (properties ? 'featureKey' OR properties ? 'feature')
          GROUP BY merchant_id, day, feature_key
        ),
        feature_rollup AS (
          SELECT merchant_id,
                 day,
                 jsonb_object_agg(feature_key, usage_count) AS feature_adoption
          FROM feature_usage
          GROUP BY merchant_id, day
        ),
        first_seen AS (
          SELECT merchant_id,
                 MIN(date_trunc('day', occurred_at)::date) AS first_day
          FROM analytics_events
          GROUP BY merchant_id
        ),
        activity_gap AS (
          SELECT merchant_id,
                 day,
                 EXTRACT(DAY FROM (day - LAG(day) OVER (PARTITION BY merchant_id ORDER BY day))) AS gap_days
          FROM (
            SELECT DISTINCT merchant_id, date_trunc('day', occurred_at)::date AS day
            FROM analytics_events
            WHERE occurred_at >= (CURRENT_DATE - INTERVAL '30 days')
          ) d
        )
        INSERT INTO merchant_daily_kpis
          (merchant_id, day, sales_count, repeat_customers, whatsapp_usage, feature_adoption,
           paid_conversion, churn_risk_score, retention_cohort, health_score, updated_at)
        SELECT
          daily.merchant_id,
          daily.day,
          daily.sales_count,
          daily.repeat_customers,
          daily.whatsapp_usage,
          COALESCE(feature_rollup.feature_adoption, '{}'::jsonb) AS feature_adoption,
          daily.paid_conversion,
          CASE
            WHEN activity_gap.gap_days IS NULL THEN 0
            WHEN activity_gap.gap_days <= 1 THEN 5
            WHEN activity_gap.gap_days <= 3 THEN 20
            WHEN activity_gap.gap_days <= 7 THEN 40
            WHEN activity_gap.gap_days <= 14 THEN 65
            ELSE 85
          END::numeric(5,2) AS churn_risk_score,
          GREATEST(
            0,
            FLOOR(EXTRACT(DAY FROM (daily.day - COALESCE(first_seen.first_day, daily.day))) / 7)
          )::int AS retention_cohort,
          LEAST(
            100,
            (LEAST(daily.sales_count / 10.0, 1) * 40) +
            (LEAST(daily.repeat_customers / 5.0, 1) * 30) +
            (LEAST(daily.whatsapp_usage / 20.0, 1) * 20) +
            (CASE
              WHEN activity_gap.gap_days IS NULL THEN 10
              WHEN activity_gap.gap_days <= 1 THEN 10
              WHEN activity_gap.gap_days <= 3 THEN 7
              WHEN activity_gap.gap_days <= 7 THEN 4
              ELSE 1
            END)
          )::numeric(5,2) AS health_score,
          NOW() AS updated_at
        FROM daily
        LEFT JOIN feature_rollup
          ON feature_rollup.merchant_id = daily.merchant_id
         AND feature_rollup.day = daily.day
        LEFT JOIN first_seen
          ON first_seen.merchant_id = daily.merchant_id
        LEFT JOIN activity_gap
          ON activity_gap.merchant_id = daily.merchant_id
         AND activity_gap.day = daily.day
        ON CONFLICT (merchant_id, day) DO UPDATE SET
          sales_count = EXCLUDED.sales_count,
          repeat_customers = EXCLUDED.repeat_customers,
          whatsapp_usage = EXCLUDED.whatsapp_usage,
          feature_adoption = EXCLUDED.feature_adoption,
          paid_conversion = EXCLUDED.paid_conversion,
          churn_risk_score = EXCLUDED.churn_risk_score,
          retention_cohort = EXCLUDED.retention_cohort,
          health_score = EXCLUDED.health_score,
          updated_at = EXCLUDED.updated_at
        """;
    jdbcTemplate.update(sql);
  }
}
