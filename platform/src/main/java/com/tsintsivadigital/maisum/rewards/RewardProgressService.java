package com.tsintsivadigital.maisum.rewards;

import java.util.List;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class RewardProgressService {
  private final JdbcTemplate jdbcTemplate;

  public RewardProgressService(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  public RewardProgressResponse getProgress(String merchantId, String customerId) {
    Integer points;
    try {
      points = jdbcTemplate.queryForObject(
          "SELECT total_points FROM customers WHERE merchant_id = ? AND id = ?",
          Integer.class,
          merchantId,
          customerId);
    } catch (EmptyResultDataAccessException ex) {
      return null;
    }

    int currentPoints = points == null ? 0 : points;
    List<RewardRow> rewards = jdbcTemplate.query(
        "SELECT name, points_required FROM rewards "
            + "WHERE merchant_id = ? AND active = TRUE AND points_required >= ? "
            + "ORDER BY points_required ASC LIMIT 1",
        (rs, rowNum) -> new RewardRow(rs.getString("name"), rs.getInt("points_required")),
        merchantId,
        currentPoints);

    if (rewards.isEmpty()) {
      return new RewardProgressResponse(currentPoints, null, 0, 0);
    }

    RewardRow next = rewards.get(0);
    int remaining = Math.max(next.pointsRequired - currentPoints, 0);
    int progress = next.pointsRequired == 0
        ? 100
        : Math.min(100, Math.round((currentPoints * 100.0f) / next.pointsRequired));

    return new RewardProgressResponse(currentPoints, next.name, remaining, progress);
  }

  private static final class RewardRow {
    private final String name;
    private final int pointsRequired;

    private RewardRow(String name, int pointsRequired) {
      this.name = name;
      this.pointsRequired = pointsRequired;
    }
  }
}
