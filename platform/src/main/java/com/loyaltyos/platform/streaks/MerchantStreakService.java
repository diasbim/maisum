package com.loyaltyos.platform.streaks;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class MerchantStreakService {
  private final JdbcTemplate jdbcTemplate;

  public MerchantStreakService(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  public void recordSale(String merchantId, Instant occurredAt) {
    LocalDate saleDay = occurredAt.atZone(ZoneOffset.UTC).toLocalDate();
    MerchantStreakRow existing = loadRow(merchantId);

    int nextStreak = 1;
    if (existing != null && existing.lastActiveDay != null) {
      long gap = ChronoUnit.DAYS.between(existing.lastActiveDay, saleDay);
      if (gap <= 0) {
        return;
      }
      if (gap == 1 || gap == 2) {
        nextStreak = existing.streakDays + 1;
      }
    }

    Instant now = Instant.now();
    jdbcTemplate.update(
        "INSERT INTO merchant_streaks (merchant_id, streak_days, last_active_day, updated_at) "
            + "VALUES (?, ?, ?, ?) ON CONFLICT (merchant_id) DO UPDATE SET "
            + "streak_days = EXCLUDED.streak_days, last_active_day = EXCLUDED.last_active_day, "
            + "updated_at = EXCLUDED.updated_at",
        merchantId,
        nextStreak,
        Date.valueOf(saleDay),
        Timestamp.from(now));

    jdbcTemplate.update(
        "UPDATE merchants SET streak_days = ?, updated_at = ? WHERE id = ?",
        nextStreak,
        Timestamp.from(now),
        merchantId);
  }

  public MerchantStreakResponse getStreak(String merchantId) {
    MerchantStreakRow row = loadRow(merchantId);
    if (row == null) {
      return new MerchantStreakResponse(0, null);
    }
    return new MerchantStreakResponse(row.streakDays, row.lastActiveDay);
  }

  private MerchantStreakRow loadRow(String merchantId) {
    List<MerchantStreakRow> rows = jdbcTemplate.query(
        "SELECT streak_days, last_active_day FROM merchant_streaks WHERE merchant_id = ?",
        (rs, rowNum) -> {
          LocalDate day = null;
          Date date = rs.getDate("last_active_day");
          if (date != null) {
            day = date.toLocalDate();
          }
          return new MerchantStreakRow(rs.getInt("streak_days"), day);
        },
        merchantId);
    return rows.isEmpty() ? null : rows.get(0);
  }

  private static final class MerchantStreakRow {
    private final int streakDays;
    private final LocalDate lastActiveDay;

    private MerchantStreakRow(int streakDays, LocalDate lastActiveDay) {
      this.streakDays = streakDays;
      this.lastActiveDay = lastActiveDay;
    }
  }
}
