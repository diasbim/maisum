package com.tsintsivadigital.maisum.common;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

public final class HashingUtils {
  private HashingUtils() {}

  public static int stableHash(String seed) {
    try {
      MessageDigest digest = MessageDigest.getInstance("SHA-256");
      byte[] hash = digest.digest(seed.getBytes(StandardCharsets.UTF_8));
      int value = 0;
      for (int i = 0; i < 4; i++) {
        value = (value << 8) | (hash[i] & 0xff);
      }
      return value;
    } catch (NoSuchAlgorithmException ex) {
      throw new IllegalStateException("SHA-256 unavailable", ex);
    }
  }
}
