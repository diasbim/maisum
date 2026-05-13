package com.loyaltyos.platform.config.repo;

import com.loyaltyos.platform.config.domain.ExperimentAssignment;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ExperimentAssignmentRepository extends JpaRepository<ExperimentAssignment, UUID> {
  Optional<ExperimentAssignment> findByConfigKeyAndMerchantId(String configKey, String merchantId);
}
