package com.tsintsivadigital.maisum.common;

import java.util.Collections;
import java.util.Map;

public class MerchantContext {
  private final String merchantId;
  private final String plan;
  private final String region;
  private final String appVersion;
  private final String deviceId;
  private final Map<String, String> attributes;

  public MerchantContext(
      String merchantId,
      String plan,
      String region,
      String appVersion,
      String deviceId,
      Map<String, String> attributes) {
    this.merchantId = merchantId;
    this.plan = plan;
    this.region = region;
    this.appVersion = appVersion;
    this.deviceId = deviceId;
    this.attributes = attributes == null ? Collections.emptyMap() : attributes;
  }

  public String getMerchantId() {
    return merchantId;
  }

  public String getPlan() {
    return plan;
  }

  public String getRegion() {
    return region;
  }

  public String getAppVersion() {
    return appVersion;
  }

  public String getDeviceId() {
    return deviceId;
  }

  public Map<String, String> getAttributes() {
    return attributes;
  }
}
