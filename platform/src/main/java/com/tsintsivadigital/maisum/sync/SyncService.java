package com.tsintsivadigital.maisum.sync;

import com.tsintsivadigital.maisum.streaks.MerchantStreakService;
import com.tsintsivadigital.maisum.sync.dto.SyncMutationRequest;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

@Service
public class SyncService {
  private static final int DEFAULT_LIMIT = 200;
  private static final int MAX_LIMIT = 500;

  private final JdbcTemplate jdbcTemplate;
  private final MerchantStreakService streakService;

  private static final Map<String, SyncEntitySchema> ENTITY_SCHEMAS =
      Map.of(
          "customer",
          new SyncEntitySchema(
              "customers",
              "updated_at",
              List.of(
                  "id",
                  "merchant_id",
                  "name",
                  "phone",
                  "total_points",
                  "created_at",
                  "updated_at"),
              Set.of("created_at", "updated_at"),
              Set.of()),
          "sale",
          new SyncEntitySchema(
              "sales",
              "created_at",
              List.of(
                  "id",
                  "merchant_id",
                  "customer_id",
                  "amount",
                  "points",
                  "created_at",
                  "device_id"),
              Set.of("created_at"),
              Set.of()),
          "reward",
          new SyncEntitySchema(
              "rewards",
              "updated_at",
              List.of(
                  "id",
                  "merchant_id",
                  "name",
                  "points_required",
                  "description",
                  "active",
                  "created_at",
                  "updated_at"),
              Set.of("created_at", "updated_at"),
              Set.of("active")),
          "redemption",
          new SyncEntitySchema(
              "redemptions",
              "redeemed_at",
              List.of(
                  "id",
                  "merchant_id",
                  "customer_id",
                  "reward_id",
                  "points_spent",
                  "redeemed_at"),
              Set.of("redeemed_at"),
              Set.of()),
            "appointment",
            new SyncEntitySchema(
              "appointments",
              "updated_at",
              List.of(
                "id",
                "merchant_id",
                "customer_id",
                "scheduled_date",
                "status",
                "source",
                "reminder_sent",
                "created_at",
                "updated_at"),
              Set.of("scheduled_date", "created_at", "updated_at"),
              Set.of("reminder_sent")),
            "retention_metric",
            new SyncEntitySchema(
              "retention_metrics",
              "updated_at",
              List.of(
                "id",
                "merchant_id",
                "customer_id",
                "last_visit_at",
                "days_inactive",
                "risk_level",
                "total_visits",
                "average_visit_interval",
                "total_spent",
                "is_recurring",
                "recovered",
                "updated_at"),
              Set.of("last_visit_at", "updated_at"),
              Set.of("is_recurring", "recovered")));

  public SyncService(JdbcTemplate jdbcTemplate, MerchantStreakService streakService) {
    this.jdbcTemplate = jdbcTemplate;
    this.streakService = streakService;
  }

  public boolean supports(String entityType) {
    return ENTITY_SCHEMAS.containsKey(entityType);
  }

  public int normalizeLimit(Integer limit) {
    if (limit == null || limit <= 0) {
      return DEFAULT_LIMIT;
    }
    return Math.min(limit, MAX_LIMIT);
  }

  public List<Map<String, Object>> fetchAll(String merchantId, String entityType, int limit) {
    SyncEntitySchema schema = ENTITY_SCHEMAS.get(entityType);
    if (schema == null) {
      return Collections.emptyList();
    }
    String sql = String.format(
        "SELECT %s FROM %s WHERE merchant_id = ? ORDER BY %s ASC, id ASC LIMIT ?",
        schema.selectClause(),
        schema.table,
        schema.orderField);
    List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql, merchantId, limit);
    return normalizeRows(rows);
  }

  public List<Map<String, Object>> fetchChanges(
      String merchantId,
      String entityType,
      String orderField,
      Long lastValue,
      String lastDocId,
      int limit) {
    SyncEntitySchema schema = ENTITY_SCHEMAS.get(entityType);
    if (schema == null) {
      return Collections.emptyList();
    }

    StringBuilder sql = new StringBuilder(
        String.format(
            "SELECT %s FROM %s WHERE merchant_id = ?",
            schema.selectClause(),
            schema.table));
    List<Object> args = new ArrayList<>();
    args.add(merchantId);

    if (lastValue != null) {
      Object cursor = normalizeOrderValue(schema, lastValue);
      if (lastDocId != null && !lastDocId.isBlank()) {
        sql.append(String.format(
            " AND (%s > ? OR (%s = ? AND id > ?))",
            schema.orderField,
            schema.orderField));
        args.add(cursor);
        args.add(cursor);
        args.add(lastDocId);
      } else {
        sql.append(String.format(" AND %s > ?", schema.orderField));
        args.add(cursor);
      }
    }

    sql.append(String.format(" ORDER BY %s ASC, id ASC LIMIT ?", schema.orderField));
    args.add(limit);

    List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql.toString(), args.toArray());
    return normalizeRows(rows);
  }

  public void applyMutation(
      String merchantId,
      String entityType,
      String entityId,
      SyncMutationRequest request) {
    SyncEntitySchema schema = ENTITY_SCHEMAS.get(entityType);
    if (schema == null) {
      return;
    }
    String operation = request.getOperation() == null ? "" : request.getOperation().toLowerCase(Locale.ROOT);
    if (operation.equals("delete")) {
      deleteEntity(schema, merchantId, entityId);
      return;
    }

    Map<String, Object> payload = new HashMap<>();
    if (request.getPayload() != null) {
      payload.putAll(request.getPayload());
    }
    payload.put("id", entityId);
    payload.put("merchant_id", merchantId);

    Map<String, Object> normalized = normalizePayload(payload, schema);
    jdbcTemplate.update(schema.upsertSql(), schema.toSqlArgs(normalized));

    if (entityType.equals("sale")) {
      Instant saleTime = toInstant(normalized.get("created_at"));
      if (saleTime != null) {
        streakService.recordSale(merchantId, saleTime);
      }
    }
  }

  private void deleteEntity(SyncEntitySchema schema, String merchantId, String entityId) {
    String sql = String.format("DELETE FROM %s WHERE merchant_id = ? AND id = ?", schema.table);
    jdbcTemplate.update(sql, merchantId, entityId);
  }

  private Map<String, Object> normalizePayload(Map<String, Object> payload, SyncEntitySchema schema) {
    Map<String, Object> normalized = new LinkedHashMap<>();
    Instant now = Instant.now();
    for (String column : schema.columns) {
      Object value = payload.get(column);
      if (value == null && schema.timestampColumns.contains(column)) {
        value = now;
      }
      normalized.put(column, normalizeValue(column, value, schema));
    }
    return normalized;
  }

  private Object normalizeValue(String column, Object value, SyncEntitySchema schema) {
    if (value == null) {
      return null;
    }
    if (schema.timestampColumns.contains(column)) {
      return normalizeTimestamp(value);
    }
    if (schema.booleanColumns.contains(column)) {
      return normalizeBoolean(value);
    }
    return value;
  }

  private Timestamp normalizeTimestamp(Object value) {
    if (value instanceof Timestamp timestamp) {
      return timestamp;
    }
    if (value instanceof Instant instant) {
      return Timestamp.from(instant);
    }
    if (value instanceof Number number) {
      return Timestamp.from(Instant.ofEpochMilli(number.longValue()));
    }
    if (value instanceof String text) {
      try {
        return Timestamp.from(Instant.parse(text));
      } catch (DateTimeParseException ex) {
        return null;
      }
    }
    return null;
  }

  private Boolean normalizeBoolean(Object value) {
    if (value instanceof Boolean bool) {
      return bool;
    }
    if (value instanceof Number number) {
      return number.intValue() != 0;
    }
    if (value instanceof String text) {
      return text.equalsIgnoreCase("true") || text.equals("1");
    }
    return null;
  }

  private Object normalizeOrderValue(SyncEntitySchema schema, Long lastValue) {
    if (schema.timestampColumns.contains(schema.orderField)) {
      return Timestamp.from(Instant.ofEpochMilli(lastValue));
    }
    return lastValue;
  }

  private List<Map<String, Object>> normalizeRows(List<Map<String, Object>> rows) {
    return rows.stream().map(this::normalizeRow).collect(Collectors.toList());
  }

  private Map<String, Object> normalizeRow(Map<String, Object> row) {
    Map<String, Object> normalized = new LinkedHashMap<>();
    for (Map.Entry<String, Object> entry : row.entrySet()) {
      normalized.put(entry.getKey().toLowerCase(Locale.ROOT), entry.getValue());
    }
    return normalized;
  }

  private Instant toInstant(Object value) {
    if (value instanceof Timestamp timestamp) {
      return timestamp.toInstant();
    }
    if (value instanceof Instant instant) {
      return instant;
    }
    return null;
  }

  private static final class SyncEntitySchema {
    private final String table;
    private final String orderField;
    private final List<String> columns;
    private final Set<String> timestampColumns;
    private final Set<String> booleanColumns;
    private final String selectClause;
    private final String upsertSql;

    private SyncEntitySchema(
        String table,
        String orderField,
        List<String> columns,
        Set<String> timestampColumns,
        Set<String> booleanColumns) {
      this.table = table;
      this.orderField = orderField;
      this.columns = columns;
      this.timestampColumns = timestampColumns;
      this.booleanColumns = booleanColumns;
      this.selectClause = buildSelectClause();
      this.upsertSql = buildUpsertSql();
    }

    private String selectClause() {
      return selectClause;
    }

    private String upsertSql() {
      return upsertSql;
    }

    private Object[] toSqlArgs(Map<String, Object> values) {
      return columns.stream().map(values::get).toArray();
    }

    private String buildSelectClause() {
      return columns.stream().map(this::selectExpression).collect(Collectors.joining(", "));
    }

    private String selectExpression(String column) {
      if (timestampColumns.contains(column)) {
        return "CAST(EXTRACT(EPOCH FROM " + column + ") * 1000 AS BIGINT) AS " + column;
      }
      if (booleanColumns.contains(column)) {
        return "CASE WHEN " + column + " THEN 1 ELSE 0 END AS " + column;
      }
      return column;
    }

    private String buildUpsertSql() {
      String columnList = String.join(", ", columns);
      String placeholders = columns.stream().map(col -> "?").collect(Collectors.joining(", "));
      String updates = columns.stream()
          .filter(col -> !col.equals("id"))
          .map(col -> col + " = EXCLUDED." + col)
          .collect(Collectors.joining(", "));
      return String.format(
          "INSERT INTO %s (%s) VALUES (%s) ON CONFLICT (id) DO UPDATE SET %s",
          table,
          columnList,
          placeholders,
          updates);
    }
  }
}
