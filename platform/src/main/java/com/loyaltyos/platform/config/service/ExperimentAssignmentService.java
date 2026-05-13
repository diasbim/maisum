package com.loyaltyos.platform.config.service;

import com.loyaltyos.platform.config.domain.ExperimentAssignment;
import com.loyaltyos.platform.config.repo.ExperimentAssignmentRepository;
import java.time.Instant;
import java.util.UUID;
import org.springframework.stereotype.Service;

@Service
public class ExperimentAssignmentService {
  private final ExperimentAssignmentRepository repository;

  public ExperimentAssignmentService(ExperimentAssignmentRepository repository) {
    this.repository = repository;
  }

  public String getOrAssign(String configKey, String merchantId, String variant) {
    return repository.findByConfigKeyAndMerchantId(configKey, merchantId)
        .map(ExperimentAssignment::getVariant)
        .orElseGet(() -> assign(configKey, merchantId, variant));
  }

  private String assign(String configKey, String merchantId, String variant) {
    ExperimentAssignment assignment = new ExperimentAssignment();
    assignment.setId(UUID.randomUUID());
    assignment.setConfigKey(configKey);
    assignment.setMerchantId(merchantId);
    assignment.setVariant(variant);
    assignment.setAssignedAt(Instant.now());
    repository.save(assignment);
    return variant;
  }
}
