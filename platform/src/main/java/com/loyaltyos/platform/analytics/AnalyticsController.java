package com.loyaltyos.platform.analytics;

import com.loyaltyos.platform.analytics.dto.AnalyticsEventRequest;
import com.loyaltyos.platform.common.MerchantContext;
import com.loyaltyos.platform.common.MerchantContextResolver;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/analytics")
public class AnalyticsController {
  private final AnalyticsIngestionService ingestionService;
  private final MerchantContextResolver contextResolver;

  public AnalyticsController(
      AnalyticsIngestionService ingestionService,
      MerchantContextResolver contextResolver) {
    this.ingestionService = ingestionService;
    this.contextResolver = contextResolver;
  }

  @PostMapping("/events")
  public ResponseEntity<Void> ingestEvents(
      @RequestHeader HttpHeaders headers,
      @Valid @RequestBody List<AnalyticsEventRequest> events) {
    MerchantContext context = contextResolver.fromHeaders(headers);
    if (context.getMerchantId() == null || context.getMerchantId().isBlank()) {
      return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
    }
    ingestionService.ingest(context.getMerchantId(), events);
    return ResponseEntity.accepted().build();
  }
}
