package com.tsintsivadigital.maisum.sync;

import com.tsintsivadigital.maisum.common.MerchantContext;
import com.tsintsivadigital.maisum.common.MerchantContextResolver;
import com.tsintsivadigital.maisum.sync.dto.SyncMutationRequest;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/sync")
public class SyncController {
  private final SyncService syncService;
  private final MerchantContextResolver contextResolver;

  public SyncController(SyncService syncService, MerchantContextResolver contextResolver) {
    this.syncService = syncService;
    this.contextResolver = contextResolver;
  }

  @GetMapping("/{entityType}")
  public ResponseEntity<List<Map<String, Object>>> fetchAll(
      @RequestHeader HttpHeaders headers,
      @PathVariable String entityType,
      @RequestParam(value = "limit", required = false) Integer limit) {
    MerchantContext context = contextResolver.fromHeaders(headers);
    if (context.getMerchantId() == null || context.getMerchantId().isBlank()) {
      return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
    }
    if (!syncService.supports(entityType)) {
      return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }
    int size = syncService.normalizeLimit(limit);
    return ResponseEntity.ok(syncService.fetchAll(context.getMerchantId(), entityType, size));
  }

  @GetMapping("/{entityType}/changes")
  public ResponseEntity<List<Map<String, Object>>> fetchChanges(
      @RequestHeader HttpHeaders headers,
      @PathVariable String entityType,
      @RequestParam(value = "order_field", required = false) String orderField,
      @RequestParam(value = "last_value", required = false) Long lastValue,
      @RequestParam(value = "last_doc_id", required = false) String lastDocId,
      @RequestParam(value = "limit", required = false) Integer limit) {
    MerchantContext context = contextResolver.fromHeaders(headers);
    if (context.getMerchantId() == null || context.getMerchantId().isBlank()) {
      return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
    }
    if (!syncService.supports(entityType)) {
      return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }
    int size = syncService.normalizeLimit(limit);
    return ResponseEntity.ok(
        syncService.fetchChanges(context.getMerchantId(), entityType, orderField, lastValue, lastDocId, size));
  }

  @PostMapping("/{entityType}/{entityId}")
  public ResponseEntity<Void> upsert(
      @RequestHeader HttpHeaders headers,
      @PathVariable String entityType,
      @PathVariable String entityId,
      @Valid @RequestBody SyncMutationRequest request) {
    MerchantContext context = contextResolver.fromHeaders(headers);
    if (context.getMerchantId() == null || context.getMerchantId().isBlank()) {
      return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
    }
    if (!syncService.supports(entityType)) {
      return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }
    syncService.applyMutation(context.getMerchantId(), entityType, entityId, request);
    return ResponseEntity.accepted().build();
  }
}
