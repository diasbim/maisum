package com.loyaltyos.platform.config.service;

import com.loyaltyos.platform.common.MerchantContext;
import com.loyaltyos.platform.config.api.dto.ConfigSnapshotResponse;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

@Service
public class ConfigSnapshotService {
  private final ConfigEvaluationService evaluationService;
  private final CacheManager cacheManager;

  public ConfigSnapshotService(ConfigEvaluationService evaluationService, CacheManager cacheManager) {
    this.evaluationService = evaluationService;
    this.cacheManager = cacheManager;
  }

  @Cacheable(cacheNames = "config-snapshot", key = "#context.merchantId")
  public ConfigSnapshotResponse getSnapshot(MerchantContext context) {
    return evaluationService.evaluate(context);
  }

  public void evictAll() {
    Cache cache = cacheManager.getCache("config-snapshot");
    if (cache != null) {
      cache.clear();
    }
  }
}
