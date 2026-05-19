package com.tsintsivadigital.maisum.config.api;

import com.tsintsivadigital.maisum.common.MerchantContext;
import com.tsintsivadigital.maisum.common.MerchantContextResolver;
import com.tsintsivadigital.maisum.config.api.dto.ConfigSnapshotResponse;
import com.tsintsivadigital.maisum.config.service.ConfigRevisionService;
import com.tsintsivadigital.maisum.config.service.ConfigSnapshotService;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/config")
public class ConfigSnapshotController {
  private final ConfigSnapshotService snapshotService;
  private final ConfigRevisionService revisionService;
  private final MerchantContextResolver contextResolver;

  public ConfigSnapshotController(
      ConfigSnapshotService snapshotService,
      ConfigRevisionService revisionService,
      MerchantContextResolver contextResolver) {
    this.snapshotService = snapshotService;
    this.revisionService = revisionService;
    this.contextResolver = contextResolver;
  }

  @GetMapping("/snapshot")
  public ResponseEntity<ConfigSnapshotResponse> getSnapshot(
      @RequestHeader HttpHeaders headers,
      @RequestHeader(value = "If-None-Match", required = false) String ifNoneMatch) {
    MerchantContext context = contextResolver.fromHeaders(headers);
    String revision = revisionService.currentRevision();
    String etag = "W/\"" + revision + "\"";
    if (etag.equals(ifNoneMatch)) {
      return ResponseEntity.status(HttpStatus.NOT_MODIFIED).eTag(etag).build();
    }
    ConfigSnapshotResponse snapshot = snapshotService.getSnapshot(context);
    return ResponseEntity.ok().eTag(etag).body(snapshot);
  }
}
