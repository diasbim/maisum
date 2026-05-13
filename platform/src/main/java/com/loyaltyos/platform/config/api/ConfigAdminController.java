package com.loyaltyos.platform.config.api;

import com.loyaltyos.platform.config.api.dto.ConfigItemRequest;
import com.loyaltyos.platform.config.api.dto.ConfigRuleRequest;
import com.loyaltyos.platform.config.api.dto.ConfigSegmentRequest;
import com.loyaltyos.platform.config.domain.ConfigItem;
import com.loyaltyos.platform.config.domain.ConfigRule;
import com.loyaltyos.platform.config.domain.ConfigSegment;
import com.loyaltyos.platform.config.repo.ConfigItemRepository;
import com.loyaltyos.platform.config.repo.ConfigRuleRepository;
import com.loyaltyos.platform.config.repo.ConfigSegmentRepository;
import com.loyaltyos.platform.config.service.AdminAuthService;
import com.loyaltyos.platform.config.service.ConfigSnapshotService;
import jakarta.validation.Valid;
import java.time.Instant;
import java.util.UUID;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/admin")
public class ConfigAdminController {
  private final AdminAuthService adminAuthService;
  private final ConfigItemRepository itemRepository;
  private final ConfigRuleRepository ruleRepository;
  private final ConfigSegmentRepository segmentRepository;
  private final ConfigSnapshotService snapshotService;

  public ConfigAdminController(
      AdminAuthService adminAuthService,
      ConfigItemRepository itemRepository,
      ConfigRuleRepository ruleRepository,
      ConfigSegmentRepository segmentRepository,
      ConfigSnapshotService snapshotService) {
    this.adminAuthService = adminAuthService;
    this.itemRepository = itemRepository;
    this.ruleRepository = ruleRepository;
    this.segmentRepository = segmentRepository;
    this.snapshotService = snapshotService;
  }

  @PostMapping("/config-items")
  public ConfigItem upsertItem(
      @RequestHeader(value = "X-Admin-Key", required = false) String adminKey,
      @Valid @RequestBody ConfigItemRequest request) {
    adminAuthService.assertAuthorized(adminKey);
    Instant now = Instant.now();
    ConfigItem item = itemRepository.findByKey(request.getKey()).orElseGet(ConfigItem::new);
    if (item.getId() == null) {
      item.setId(UUID.randomUUID());
      item.setCreatedAt(now);
    }
    item.setKey(request.getKey());
    item.setType(request.getType());
    item.setEnabled(request.isEnabled());
    item.setDefaultPayload(request.getDefaultPayload());
    item.setUpdatedAt(now);
    ConfigItem saved = itemRepository.save(item);
    snapshotService.evictAll();
    return saved;
  }

  @PostMapping("/config-segments")
  public ConfigSegment upsertSegment(
      @RequestHeader(value = "X-Admin-Key", required = false) String adminKey,
      @Valid @RequestBody ConfigSegmentRequest request) {
    adminAuthService.assertAuthorized(adminKey);
    Instant now = Instant.now();
    ConfigSegment segment = new ConfigSegment();
    segment.setId(UUID.randomUUID());
    segment.setName(request.getName());
    segment.setEnabled(request.isEnabled());
    segment.setConditions(request.getConditions());
    segment.setCreatedAt(now);
    segment.setUpdatedAt(now);
    ConfigSegment saved = segmentRepository.save(segment);
    snapshotService.evictAll();
    return saved;
  }

  @PostMapping("/config-rules")
  public ConfigRule createRule(
      @RequestHeader(value = "X-Admin-Key", required = false) String adminKey,
      @Valid @RequestBody ConfigRuleRequest request) {
    adminAuthService.assertAuthorized(adminKey);
    Instant now = Instant.now();
    ConfigRule rule = new ConfigRule();
    rule.setId(UUID.randomUUID());
    rule.setConfigKey(request.getConfigKey());
    rule.setSegmentId(request.getSegmentId());
    rule.setPriority(request.getPriority());
    rule.setRolloutPct(request.getRolloutPct());
    rule.setEnabled(request.isEnabled());
    rule.setPayloadOverride(request.getPayloadOverride());
    rule.setStartsAt(request.getStartsAt());
    rule.setEndsAt(request.getEndsAt());
    rule.setCreatedAt(now);
    rule.setUpdatedAt(now);
    ConfigRule saved = ruleRepository.save(rule);
    snapshotService.evictAll();
    return saved;
  }
}
