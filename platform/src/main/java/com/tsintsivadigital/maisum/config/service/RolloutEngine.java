package com.tsintsivadigital.maisum.config.service;

import com.tsintsivadigital.maisum.common.HashingUtils;
import org.springframework.stereotype.Component;

@Component
public class RolloutEngine {
  public boolean isInRollout(String seed, int rolloutPct) {
    if (rolloutPct >= 100) {
      return true;
    }
    if (rolloutPct <= 0) {
      return false;
    }
    int bucket = Math.floorMod(HashingUtils.stableHash(seed), 100);
    return bucket < rolloutPct;
  }
}
