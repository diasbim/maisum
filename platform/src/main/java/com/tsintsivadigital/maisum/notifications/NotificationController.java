package com.tsintsivadigital.maisum.notifications;

import com.tsintsivadigital.maisum.common.MerchantContext;
import com.tsintsivadigital.maisum.common.MerchantContextResolver;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/notifications")
public class NotificationController {
  private final NotificationService notificationService;
  private final MerchantContextResolver contextResolver;

  public NotificationController(
      NotificationService notificationService,
      MerchantContextResolver contextResolver) {
    this.notificationService = notificationService;
    this.contextResolver = contextResolver;
  }

  @PostMapping("/queue")
  public ResponseEntity<NotificationResponse> queue(
      @RequestHeader HttpHeaders headers,
      @Valid @RequestBody NotificationRequest request) {
    MerchantContext context = contextResolver.fromHeaders(headers);
    if (context.getMerchantId() == null || context.getMerchantId().isBlank()) {
      return ResponseEntity.status(HttpStatus.BAD_REQUEST).build();
    }

    UUID id = notificationService.enqueue(context.getMerchantId(), request);
    return ResponseEntity.accepted().body(new NotificationResponse(id));
  }
}
