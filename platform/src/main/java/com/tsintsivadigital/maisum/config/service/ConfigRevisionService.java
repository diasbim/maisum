package com.tsintsivadigital.maisum.config.service;

import java.sql.Timestamp;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class ConfigRevisionService {
  private final JdbcTemplate jdbcTemplate;

  public ConfigRevisionService(JdbcTemplate jdbcTemplate) {
    this.jdbcTemplate = jdbcTemplate;
  }

  public String currentRevision() {
    String sql = "SELECT GREATEST("
        + "COALESCE((SELECT MAX(updated_at) FROM config_items), 'epoch'::timestamptz),"
        + "COALESCE((SELECT MAX(updated_at) FROM config_rules), 'epoch'::timestamptz),"
        + "COALESCE((SELECT MAX(updated_at) FROM config_segments), 'epoch'::timestamptz)"
        + ")";
    Timestamp timestamp = jdbcTemplate.queryForObject(sql, Timestamp.class);
    if (timestamp == null) {
      return "0";
    }
    return String.valueOf(timestamp.toInstant().toEpochMilli());
  }
}
