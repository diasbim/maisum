package com.tsintsivadigital.maisum.rewards;

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
@RequestMapping("/customers")
public class RewardProgressController {
  private final RewardProgressService progressService;
  private final MerchantContextResolver contextResolver;

  public RewardProgressController(
      RewardProgressService progressService,
      MerchantContextResolver contextResolver) {
    this.progressService = progressService;
    this.contextResolver = contextResolver;
  }

  @GetMapping("/{customerId}/reward-progress")
  public ResponseEntity<RewardProgressResponse> getProgress(
      @RequestHeader HttpHeaders headers,
      @PathVariable String customerId) {
    MerchantContext context = contextResolver.fromHeaders(headers);
    if (context.getMerchantId() == null || context.getMerchantId().isBlank()) {
      return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
    }

    RewardProgressResponse response =
        progressService.getProgress(context.getMerchantId(), customerId);
    if (response == null) {
      return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
    }

    return ResponseEntity.ok(response);
  }
}
