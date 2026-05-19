package com.tsintsivadigital.maisum.config.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class AdminAuthService {
  @Value("${platform.admin.apiKey:}")
  private String apiKey;

  public void assertAuthorized(String providedKey) {
    if (apiKey == null || apiKey.isBlank()) {
      return;
    }
    if (providedKey == null || !apiKey.equals(providedKey)) {
      throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid admin key");
    }
  }
}
