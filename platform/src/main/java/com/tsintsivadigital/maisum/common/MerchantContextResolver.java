package com.tsintsivadigital.maisum.common;

import java.util.HashMap;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;

@Component
public class MerchantContextResolver {
  public MerchantContext fromHeaders(HttpHeaders headers) {
    String merchantId = headers.getFirst("X-Merchant-Id");
    String plan = headers.getFirst("X-Plan");
    String region = headers.getFirst("X-Region");
    String appVersion = headers.getFirst("X-App-Version");
    String deviceId = headers.getFirst("X-Device-Id");
    Map<String, String> attributes = new HashMap<>();
    for (String header : headers.keySet()) {
      if (header == null || !header.startsWith("X-Attr-")) {
        continue;
      }
      attributes.put(header.substring("X-Attr-".length()), headers.getFirst(header));
    }
    return new MerchantContext(merchantId, plan, region, appVersion, deviceId, attributes);
  }
}
