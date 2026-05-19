package com.tsintsivadigital.maisum.streaks;

import com.tsintsivadigital.maisum.common.MerchantContext;
import com.tsintsivadigital.maisum.common.MerchantContextResolver;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/merchants")
public class MerchantStreakController {
  private final MerchantStreakService streakService;
  private final MerchantContextResolver contextResolver;

  public MerchantStreakController(
      MerchantStreakService streakService,
      MerchantContextResolver contextResolver) {
    this.streakService = streakService;
    this.contextResolver = contextResolver;
  }

  @GetMapping("/{merchantId}/streak")
  public ResponseEntity<MerchantStreakResponse> getStreak(
      @RequestHeader HttpHeaders headers,
      @PathVariable String merchantId) {
    MerchantContext context = contextResolver.fromHeaders(headers);
    if (context.getMerchantId() == null || context.getMerchantId().isBlank()) {
      return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
    }
    if (!context.getMerchantId().equals(merchantId)) {
      return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
    }
    return ResponseEntity.ok(streakService.getStreak(merchantId));
  }
}
